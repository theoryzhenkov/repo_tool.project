import argparse
import getpass
import json
import os
import pwd
import shutil
import subprocess
import sys
import time
import uuid
from pathlib import Path

def load_catalog():
  with open(os.environ["PROJECT_CATALOG_JSON"], "r", encoding="utf-8") as fh:
    return json.load(fh)

CATALOG = load_catalog()
ROOT = Path(os.environ["PROJECT_APPROVAL_ROOT"])
SETFACL = os.environ["SETFACL"]
REQUESTS = ROOT / "requests"
RESULTS = ROOT / "results"
GRANTS = ROOT / "grants"

def fail(message, code=64):
  print(f"project: {message}", file=sys.stderr)
  raise SystemExit(code)

def now():
  return int(time.time())

def parse_ttl(value):
  value = value.strip().lower()
  if not value:
    fail("empty ttl")
  unit = value[-1]
  if unit in "smhd":
    amount = value[:-1]
    factor = {"s": 1, "m": 60, "h": 3600, "d": 86400}[unit]
  else:
    amount = value
    factor = 1
  try:
    seconds = int(amount) * factor
  except ValueError:
    fail(f"invalid ttl: {value}")
  if seconds <= 0:
    fail("ttl must be positive")
  return seconds

def user_from_uid(uid):
  return pwd.getpwuid(uid).pw_name

def current_user():
  return pwd.getpwuid(os.getuid()).pw_name

def project_user(name, project):
  if project.get("user"):
    return project["user"]
  return os.environ.get("PROJECT_USER_PREFIX", "usr.prj_") + name

def project_home(name, project):
  if project.get("home"):
    return project["home"]
  return "/home/" + project_user(name, project)

def project_workdir(name, project):
  if project.get("workDir"):
    return project["workDir"]
  return project_home(name, project) + "/" + os.environ.get("PROJECT_WORKDIR_NAME", "src")

def resolve_project(name):
  if name in CATALOG:
    return name
  matches = [project_name for project_name, project in CATALOG.items() if name in project.get("aliases", [])]
  if len(matches) == 1:
    return matches[0]
  if len(matches) > 1:
    fail(f"ambiguous project alias: {name}")
  fail(f"unknown project: {name}")

def ensure_dirs():
  for path in [REQUESTS, RESULTS, GRANTS]:
    path.mkdir(parents=True, exist_ok=True)

def request_path(request_id):
  return REQUESTS / request_id / "request.json"

def grant_path(grant_id):
  return GRANTS / f"{grant_id}.json"

def result_path(request_id):
  return RESULTS / f"{request_id}.json"

def write_request(payload):
  ensure_dirs()
  request_id = uuid.uuid4().hex[:12]
  directory = REQUESTS / request_id
  directory.mkdir(mode=0o700)
  payload = dict(payload)
  payload.update({
    "id": request_id,
    "requester": current_user(),
    "requesterUid": os.getuid(),
    "createdAt": now(),
    "cwd": os.getcwd(),
  })
  path = directory / "request.json"
  with open(path, "x", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
  os.chmod(path, 0o600)
  print(f"request {request_id} created")
  print(f"ask the owner to review with: project show {request_id}")
  print(f"and approve with:        project approve {request_id}")

def load_request(request_id):
  path = request_path(request_id)
  if not path.exists():
    fail(f"unknown request: {request_id}", 66)
  st = path.stat()
  requester = user_from_uid(st.st_uid)
  with open(path, "r", encoding="utf-8") as fh:
    request = json.load(fh)
  request["requester"] = requester
  request["requesterUid"] = st.st_uid
  return request

def close_request(request_id):
  shutil.rmtree(REQUESTS / request_id, ignore_errors=True)

def summarize_request(request):
  lines = [
    f"id:        {request['id']}",
    f"type:      {request['type']}",
    f"requester: {request['requester']}",
  ]
  if request["type"] == "access":
    lines += [
      f"project:   {request['project']}",
      f"mode:      {request.get('mode', 'read')}",
      f"ttl:       {request['ttlSeconds']}s",
    ]
  elif request["type"] == "sudo":
    lines += [
      f"cwd:       {request.get('cwd', '/')}",
      f"timeout:   {request['timeoutSeconds']}s",
      "command:   " + " ".join(request["argv"]),
    ]
  if request.get("reason"):
    lines.append(f"reason:    {request['reason']}")
  return "\n".join(lines)

def cmd_show(args):
  print(summarize_request(load_request(args.id)))

def compact_text(value, limit=160):
  text = " ".join(str(value).split())
  if len(text) > limit:
    return text[:limit - 3] + "..."
  return text

def list_summary(request):
  if request["type"] == "access":
    mode = request.get("mode", "read")
    project = request.get("project", "")
    return compact_text(f"{project} [{mode}]")
  if request["type"] == "sudo":
    return compact_text(" ".join(request.get("argv", [])))
  return ""

def cmd_list(args):
  ensure_dirs()
  mine = current_user()
  for path in sorted(REQUESTS.glob("*/request.json")):
    try:
      request = load_request(path.parent.name)
    except Exception:
      continue
    if os.geteuid() != 0 and request["requester"] != mine:
      continue
    print(f"{request['id']}\t{request['type']}\t{request['requester']}\t{list_summary(request)}")

def cmd_request_access(args):
  project = resolve_project(args.project)
  write_request({
    "type": "access",
    "project": project,
    "mode": args.mode,
    "ttlSeconds": parse_ttl(args.ttl),
    "reason": args.reason,
  })

def cmd_request_sudo(args):
  argv = args.argv
  if argv and argv[0] == "--":
    argv = argv[1:]
  if not argv:
    fail("sudo request requires a command after --")
  write_request({
    "type": "sudo",
    "argv": argv,
    "timeoutSeconds": parse_ttl(args.timeout),
    "reason": args.reason,
  })

def require_root():
  if os.geteuid() != 0:
    fail("this command must run as root; owner can use `sudo project ...`", 77)

def setfacl(*args):
  subprocess.run([SETFACL, *args], check=True)

def scope_included_projects(project_name):
  scope = CATALOG[project_name].get("scope", {})
  included = []
  if scope.get("includeDescendants"):
    prefix = project_name + "."
    included.extend(name for name in CATALOG if name.startswith(prefix))
  included.extend(scope.get("include", []))
  seen = set()
  return [name for name in included if not (name in seen or seen.add(name))]

def access_grant_projects(project_name):
  return [project_name, *scope_included_projects(project_name)]

def access_target(project_name):
  project = CATALOG[project_name]
  home = project_home(project_name, project)
  workdir = project_workdir(project_name, project)
  return {
    "project": project_name,
    "home": home,
    "workdir": workdir,
    "targetUser": project_user(project_name, project),
  }

def project_read_ancestor_dirs(home, workdir):
  home_path = Path(home)
  workdir_path = Path(workdir)
  try:
    relative = workdir_path.relative_to(home_path)
  except ValueError:
    return [home_path]
  dirs = [home_path]
  current = home_path
  for part in relative.parts[:-1]:
    current = current / part
    dirs.append(current)
  return dirs

def apply_project_read_access(target, requester):
  for directory in project_read_ancestor_dirs(target["home"], target["workdir"]):
    setfacl("-m", f"u:{requester}:x", str(directory))
  setfacl("-R", "-m", f"u:{requester}:rX,d:u:{requester}:rX", target["workdir"])

def apply_access_grant(request):
  project_name = request["project"]
  requester = request["requester"]
  expires_at = now() + int(request["ttlSeconds"])
  mode = request.get("mode", "read")
  targets = [access_target(name) for name in access_grant_projects(project_name)]
  acl_applied = mode == "read"
  if acl_applied:
    for target in targets:
      apply_project_read_access(target, requester)
  primary = targets[0]

  grant = {
    "id": request["id"],
    "requester": requester,
    "project": project_name,
    "mode": mode,
    "aclApplied": acl_applied,
    "home": primary["home"],
    "workdir": primary["workdir"],
    "targetUser": primary["targetUser"],
    "targets": targets,
    "expiresAt": expires_at,
  }
  with open(grant_path(request["id"]), "w", encoding="utf-8") as fh:
    json.dump(grant, fh, indent=2, sort_keys=True)
    fh.write("\n")
  target_count = len(targets)
  suffix = "" if target_count == 1 else f" and {target_count - 1} included project(s)"
  print(f"granted {requester} {mode} access to {project_name}{suffix} until {time.ctime(expires_at)}")

def revoke_grant(grant_id, missing_ok=False):
  path = grant_path(grant_id)
  if not path.exists():
    if missing_ok:
      return False
    fail(f"unknown grant: {grant_id}", 66)
  with open(path, "r", encoding="utf-8") as fh:
    grant = json.load(fh)
  requester = grant["requester"]
  if grant.get("aclApplied", True):
    targets = grant.get("targets") or [{"home": grant["home"], "workdir": grant["workdir"]}]
    for target in targets:
      for directory in project_read_ancestor_dirs(target["home"], target["workdir"]):
        subprocess.run([SETFACL, "-x", f"u:{requester}", str(directory)], check=False)
      subprocess.run([SETFACL, "-R", "-x", f"u:{requester}", "-x", f"d:u:{requester}", target["workdir"]], check=False)
  path.unlink()
  print(f"revoked {grant_id}: {requester} access to {grant['project']}")
  return True

def write_result(request, completed):
  payload = {
    "id": request["id"],
    "requester": request["requester"],
    "argv": request["argv"],
    "returncode": completed.returncode,
    "stdout": completed.stdout,
    "stderr": completed.stderr,
    "finishedAt": now(),
  }
  path = result_path(request["id"])
  with open(path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True)
    fh.write("\n")
  uid = pwd.getpwnam(request["requester"]).pw_uid
  gid = pwd.getpwnam(request["requester"]).pw_gid
  os.chown(path, uid, gid)
  os.chmod(path, 0o640)

def run_sudo_request(request):
  cwd = request.get("cwd") or "/"
  if not os.path.isdir(cwd):
    cwd = "/"
  completed = subprocess.run(
    request["argv"],
    cwd=cwd,
    text=True,
    capture_output=True,
    timeout=int(request["timeoutSeconds"]),
  )
  write_result(request, completed)
  print(f"command exited {completed.returncode}; requester can read: project result {request['id']}")
  if completed.stdout:
    print("--- stdout ---")
    print(completed.stdout, end="")
  if completed.stderr:
    print("--- stderr ---", file=sys.stderr)
    print(completed.stderr, end="", file=sys.stderr)

def cmd_approve(args):
  require_root()
  request = load_request(args.id)
  print(summarize_request(request))
  if not args.yes:
    answer = input("Approve this request? [y/N] ")
    if answer.lower() not in ["y", "yes"]:
      fail("not approved", 1)
  if request["type"] == "access":
    apply_access_grant(request)
  elif request["type"] == "sudo":
    run_sudo_request(request)
  else:
    fail(f"unknown request type: {request['type']}")
  close_request(request["id"])

def cmd_result(args):
  path = result_path(args.id)
  if not path.exists():
    fail(f"no result for request: {args.id}", 66)
  with open(path, "r", encoding="utf-8") as fh:
    result = json.load(fh)
  print(f"id: {result['id']}")
  print(f"returncode: {result['returncode']}")
  print("--- stdout ---")
  print(result.get("stdout", ""), end="")
  print("--- stderr ---")
  print(result.get("stderr", ""), end="")

def cmd_grants(args):
  ensure_dirs()
  for path in sorted(GRANTS.glob("*.json")):
    try:
      with open(path, "r", encoding="utf-8") as fh:
        grant = json.load(fh)
    except Exception:
      continue
    remaining = int(grant.get("expiresAt", 0)) - now()
    print(f"{grant['id']}\t{grant['requester']}\t{grant['project']}\t{max(0, remaining)}s\t{grant['workdir']}")

def grant_allows_act(grant, requester, project_name):
  if grant.get("requester") != requester:
    return False
  if grant.get("mode", "read") != "act":
    return False
  if int(grant.get("expiresAt", 0)) <= now():
    return False
  return any(target.get("project") == project_name for target in grant.get("targets", []))

def cmd_can_act(args):
  ensure_dirs()
  project_name = resolve_project(args.project)
  for path in sorted(GRANTS.glob("*.json")):
    try:
      with open(path, "r", encoding="utf-8") as fh:
        grant = json.load(fh)
    except Exception:
      continue
    if grant_allows_act(grant, args.requester, project_name):
      print(grant.get("id", path.stem))
      return
  fail(f"no active act grant for {args.requester} on {project_name}", 77)

def cmd_reject(args):
  require_root()
  request = load_request(args.id)
  print(summarize_request(request))
  close_request(args.id)
  print(f"rejected request {args.id}")

def cmd_revoke(args):
  require_root()
  revoke_grant(args.id)

def cmd_expire_grants(args):
  require_root()
  ensure_dirs()
  cutoff = now()
  for path in sorted(GRANTS.glob("*.json")):
    with open(path, "r", encoding="utf-8") as fh:
      grant = json.load(fh)
    if int(grant.get("expiresAt", 0)) <= cutoff:
      revoke_grant(path.stem, missing_ok=True)

def main(argv):
  parser = argparse.ArgumentParser(prog="project")
  sub = parser.add_subparsers(dest="command", required=True)

  req = sub.add_parser("request")
  req_sub = req.add_subparsers(dest="request_type", required=True)
  access = req_sub.add_parser("access")
  access.add_argument("project")
  access.add_argument("--mode", choices=["read", "act"], default="read")
  access.add_argument("--ttl", default="1h")
  access.add_argument("--reason", default="")
  access.set_defaults(func=cmd_request_access)
  sudo = req_sub.add_parser("sudo")
  sudo.add_argument("--timeout", default="10m")
  sudo.add_argument("--reason", default="")
  sudo.add_argument("argv", nargs=argparse.REMAINDER)
  sudo.set_defaults(func=cmd_request_sudo)

  show = sub.add_parser("show")
  show.add_argument("id")
  show.set_defaults(func=cmd_show)
  pending = sub.add_parser("requests")
  pending.set_defaults(func=cmd_list)
  approve = sub.add_parser("approve")
  approve.add_argument("id")
  approve.add_argument("--yes", action="store_true")
  approve.set_defaults(func=cmd_approve)
  result = sub.add_parser("result")
  result.add_argument("id")
  result.set_defaults(func=cmd_result)
  grants = sub.add_parser("grants")
  grants.set_defaults(func=cmd_grants)
  reject = sub.add_parser("reject")
  reject.add_argument("id")
  reject.set_defaults(func=cmd_reject)
  revoke = sub.add_parser("revoke")
  revoke.add_argument("id")
  revoke.set_defaults(func=cmd_revoke)
  can_act = sub.add_parser("can-act")
  can_act.add_argument("requester")
  can_act.add_argument("project")
  can_act.set_defaults(func=cmd_can_act)
  expire = sub.add_parser("expire-grants")
  expire.set_defaults(func=cmd_expire_grants)

  args = parser.parse_args(argv)
  args.func(args)

if __name__ == "__main__":
  main(sys.argv[1:])