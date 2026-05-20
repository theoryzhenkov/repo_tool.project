import argparse
import json
import os
import re
import shutil
import sys
import tempfile
from pathlib import Path

NAME_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
COMPONENT_RE = re.compile(r"^[A-Za-z0-9_-]+$")
USER_RE = re.compile(r"^[A-Za-z0-9_.-]+$")

def load_catalog():
  with open(os.environ["REALM_CATALOG_JSON"], "r", encoding="utf-8") as fh:
    return json.load(fh)

CATALOG = load_catalog()
USER_PREFIX = os.environ.get("REALM_PROJECT_USER_PREFIX", "usr.prj_")
DEFAULT_CATALOG_DIR = os.environ.get("REALM_CATALOG_WRITE_DIR", "")

def fail(message, code=64):
  print(f"realm: {message}", file=sys.stderr)
  raise SystemExit(code)

def validate_name(name):
  if not NAME_RE.fullmatch(name) or any(part == "" for part in name.split(".")):
    fail(f"invalid project name: {name}")
  for part in name.split("."):
    if not COMPONENT_RE.fullmatch(part):
      fail(f"invalid project path component in {name}: {part}")

def validate_alias(alias):
  if not NAME_RE.fullmatch(alias):
    fail(f"invalid alias: {alias}")

def validate_user(user):
  if not USER_RE.fullmatch(user) or len(user) > 31:
    fail(f"invalid user: {user}")

def default_user(name):
  return USER_PREFIX + name

def project_path(catalog_dir, name):
  root = Path(catalog_dir).expanduser().resolve()
  path = root.joinpath(*name.split("."), "project.nix").resolve()
  if root != path and root not in path.parents:
    fail(f"refusing to write outside catalog directory: {path}")
  return path

def copy_repo(repo):
  return {
    "aliases": list(repo.get("aliases", [])),
    "path": repo.get("path"),
    "mode": repo.get("mode", "0750"),
    "primary": repo.get("primary", False),
    "git": {
      "url": repo.get("git", {}).get("url"),
      "remote": repo.get("git", {}).get("remote", "origin"),
      "branch": repo.get("git", {}).get("branch"),
    },
    "description": repo.get("description"),
  }

def copy_project(project):
  return {
    "user": project.get("user"),
    "aliases": list(project.get("aliases", [])),
    "home": project.get("home"),
    "homeMode": project.get("homeMode", "0750"),
    "workDir": project.get("workDir"),
    "workDirMode": project.get("workDirMode", "0750"),
    "defaultRepo": project.get("defaultRepo"),
    "repos": {name: copy_repo(repo) for name, repo in project.get("repos", {}).items()},
    "scope": {
      "enable": project.get("scope", {}).get("enable", False),
      "includeDescendants": project.get("scope", {}).get("includeDescendants", False),
      "include": list(project.get("scope", {}).get("include", [])),
    },
  }

def nix_string(value):
  return json.dumps(value)

def render_list(values, indent="  "):
  if not values:
    return "[ ]"
  if len(values) == 1:
    return f"[ {nix_string(values[0])} ]"
  lines = ["["]
  for value in values:
    lines.append(f"{indent}  {nix_string(value)}")
  lines.append(f"{indent}]")
  return "\n".join(lines)

def render_repo(repo, indent="    "):
  lines = ["{"]
  if repo.get("aliases"):
    lines.append(f"{indent}aliases = {render_list(repo['aliases'], indent=indent)};")
  if repo.get("path") is not None:
    lines.append(f"{indent}path = {nix_string(repo['path'])};")
  if repo.get("mode", "0750") != "0750":
    lines.append(f"{indent}mode = {nix_string(repo['mode'])};")
  if repo.get("primary"):
    lines.append(f"{indent}primary = true;")

  git = repo.get("git", {})
  if git.get("url") is not None or git.get("remote", "origin") != "origin" or git.get("branch") is not None:
    lines.append(f"{indent}git = {{")
    if git.get("url") is not None:
      lines.append(f"{indent}  url = {nix_string(git['url'])};")
    if git.get("remote", "origin") != "origin":
      lines.append(f"{indent}  remote = {nix_string(git['remote'])};")
    if git.get("branch") is not None:
      lines.append(f"{indent}  branch = {nix_string(git['branch'])};")
    lines.append(f"{indent}}};")

  if repo.get("description") is not None:
    lines.append(f"{indent}description = {nix_string(repo['description'])};")
  lines.append("  }" if indent == "    " else f"{indent[:-2]}}}")
  return "\n".join(lines)

def render_repos_attr(name, repos):
  lines = [f"  {name} = {{"]
  for repo_name in sorted(repos):
    lines.append(f"    {nix_string(repo_name)} = {render_repo(repos[repo_name])};")
  lines.append("  };")
  return "\n".join(lines)

def render_project(project):
  lines = ["{"]
  if project.get("user") is not None:
    lines.append(f"  user = {nix_string(project['user'])};")
  if project.get("aliases"):
    lines.append(f"  aliases = {render_list(project['aliases'])};")
  if project.get("home") is not None:
    lines.append(f"  home = {nix_string(project['home'])};")
  if project.get("homeMode", "0750") != "0750":
    lines.append(f"  homeMode = {nix_string(project['homeMode'])};")
  if project.get("workDir") is not None:
    lines.append(f"  workDir = {nix_string(project['workDir'])};")
  if project.get("workDirMode", "0750") != "0750":
    lines.append(f"  workDirMode = {nix_string(project['workDirMode'])};")
  if project.get("defaultRepo") is not None:
    lines.append(f"  defaultRepo = {nix_string(project['defaultRepo'])};")
  if project.get("repos"):
    lines.append(render_repos_attr("repos", project["repos"]))
  scope = project.get("scope", {})
  if scope.get("enable") or scope.get("includeDescendants") or scope.get("include"):
    lines.append("  scope = {")
    if scope.get("enable"):
      lines.append("    enable = true;")
    if scope.get("includeDescendants"):
      lines.append("    includeDescendants = true;")
    if scope.get("include"):
      lines.append(f"    include = {render_list(scope['include'], indent='    ')};")
    lines.append("  };")
  lines.append("}")
  return "\n".join(lines) + "\n"

def lookup_space(excluding=()):
  excluded = set(excluding)
  names = set()
  for name, project in CATALOG.items():
    if name in excluded:
      continue
    names.add(name)
    names.update(project.get("aliases", []))
  return names

def validate_aliases(project_name, project, excluding=()):
  seen = set()
  occupied = lookup_space(excluding)
  for alias in project.get("aliases", []):
    validate_alias(alias)
    if alias == project_name:
      fail(f"alias duplicates the project name: {alias}")
    if alias in seen:
      fail(f"duplicate alias on realm: {alias}")
    if alias in occupied:
      fail(f"alias collides with another project or alias: {alias}")
    seen.add(alias)

def validate_project_user(project_name, project):
  user = project.get("user") or default_user(project_name)
  validate_user(user)

def validate_scope(project):
  for included in project.get("scope", {}).get("include", []):
    validate_name(included)
    if included not in CATALOG:
      fail(f"scope include references unknown realm: {included}")

def catalog_dir(args):
  value = args.catalog_dir or DEFAULT_CATALOG_DIR
  if not value:
    fail("no catalog write directory configured; pass --catalog-dir or configure REALM_CATALOG_WRITE_DIR")
  return value

def show_or_write(args, name, project, *, old_name=None):
  content = render_project(project)
  if args.write:
    path = project_path(catalog_dir(args), name)
    if old_name is None and path.exists() and getattr(args, "mode", None) == "new":
      fail(f"project file already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix="project.nix.", dir=str(path.parent))
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
      fh.write(content)
    os.replace(tmp, path)

    if old_name is not None and old_name != name:
      old_path = project_path(catalog_dir(args), old_name)
      if old_path.exists():
        old_path.unlink()
        current = old_path.parent
        root = Path(catalog_dir(args)).expanduser().resolve()
        while current != root:
          try:
            current.rmdir()
          except OSError:
            break
          current = current.parent
    print(f"wrote {path}")
    apply_message = os.environ.get("REALM_CATALOG_APPLY_MESSAGE")
    if apply_message:
      print(apply_message)
  else:
    path_label = str(project_path(args.catalog_dir or DEFAULT_CATALOG_DIR or "<catalog-dir>", name)) if (args.catalog_dir or DEFAULT_CATALOG_DIR) else f"<catalog-dir>/{'/'.join(name.split('.'))}/project.nix"
    action = "rename/write" if old_name else "write"
    print(f"would {action} {path_label}")
    print("--- project.nix ---")
    print(content, end="")

def apply_common_options(project, args):
  if getattr(args, "user", None) is not None:
    validate_user(args.user)
    project["user"] = args.user
  if getattr(args, "unset_user", False):
    project["user"] = None
  if getattr(args, "clear_aliases", False):
    project["aliases"] = []
  for alias in getattr(args, "alias", []) or []:
    validate_alias(alias)
    if alias not in project["aliases"]:
      project["aliases"].append(alias)
  scope = project["scope"]
  if getattr(args, "scope", False):
    scope["enable"] = True
    scope["includeDescendants"] = True
  if getattr(args, "no_scope", False):
    scope["enable"] = False
    scope["includeDescendants"] = False
    scope["include"] = []
  if getattr(args, "include_descendants", False):
    scope["enable"] = True
    scope["includeDescendants"] = True
  if getattr(args, "no_include_descendants", False):
    scope["includeDescendants"] = False
  if getattr(args, "clear_include", False):
    scope["include"] = []
  for included in getattr(args, "include", []) or []:
    validate_name(included)
    if included not in scope["include"]:
      scope["include"].append(included)
  return project

def cmd_new(args):
  validate_name(args.name)
  if args.name in CATALOG:
    fail(f"project already exists: {args.name}")
  if args.name in lookup_space():
    fail(f"project name collides with an existing alias: {args.name}")
  project = copy_project({})
  args.mode = "new"
  project = apply_common_options(project, args)
  validate_aliases(args.name, project)
  validate_project_user(args.name, project)
  validate_scope(project)
  show_or_write(args, args.name, project)

def cmd_edit(args):
  validate_name(args.name)
  if args.name not in CATALOG:
    fail(f"unknown realm: {args.name}")
  project = apply_common_options(copy_project(CATALOG[args.name]), args)
  validate_aliases(args.name, project, excluding=[args.name])
  validate_project_user(args.name, project)
  validate_scope(project)
  show_or_write(args, args.name, project)

def cmd_rename(args):
  validate_name(args.old_name)
  validate_name(args.new_name)
  if args.old_name not in CATALOG:
    fail(f"unknown realm: {args.old_name}")
  if args.new_name in CATALOG:
    fail(f"target project already exists: {args.new_name}")
  if args.new_name in lookup_space(excluding=[args.old_name]):
    fail(f"target project name collides with an existing alias: {args.new_name}")
  project = copy_project(CATALOG[args.old_name])
  if project.get("user") is None and not args.recompute_user:
    user = default_user(args.old_name)
    validate_user(user)
    project["user"] = user
  if args.keep_old_alias and args.old_name not in project["aliases"]:
    project["aliases"].append(args.old_name)
  project = apply_common_options(project, args)
  validate_aliases(args.new_name, project, excluding=[args.old_name])
  validate_project_user(args.new_name, project)
  validate_scope(project)
  show_or_write(args, args.new_name, project, old_name=args.old_name)

def add_common(parser):
  parser.add_argument("--alias", action="append", default=[], help="add an alias; repeatable")
  parser.add_argument("--user", help="set explicit generated Linux user name")
  parser.add_argument("--unset-user", action="store_true", help="remove explicit user override")
  parser.add_argument("--clear-aliases", action="store_true", help="remove all existing aliases")
  parser.add_argument("--scope", action="store_true", help="enable scope access and include descendants")
  parser.add_argument("--no-scope", action="store_true", help="disable scope access")
  parser.add_argument("--include-descendants", action="store_true", help="include dotted descendants in scope access")
  parser.add_argument("--no-include-descendants", action="store_true", help="do not include dotted descendants in scope access")
  parser.add_argument("--include", action="append", default=[], help="add explicit project to scope access; repeatable")
  parser.add_argument("--clear-include", action="store_true", help="remove explicit scope includes")
  parser.add_argument("--catalog-dir", help="mutable project catalog directory")
  parser.add_argument("--write", action="store_true", help="write the project.nix change instead of printing it")

def main(argv):
  parser = argparse.ArgumentParser(prog="realm-catalog")
  sub = parser.add_subparsers(dest="command", required=True)

  new = sub.add_parser("new", help="create a new project definition")
  new.add_argument("name")
  add_common(new)
  new.set_defaults(func=cmd_new)

  edit = sub.add_parser("edit", help="edit an existing project definition")
  edit.add_argument("name")
  add_common(edit)
  edit.set_defaults(func=cmd_edit)

  rename = sub.add_parser("rename", help="rename a project definition file")
  rename.add_argument("old_name")
  rename.add_argument("new_name")
  add_common(rename)
  rename.add_argument("--keep-old-alias", action="store_true", help="add the old project key as an alias")
  rename.add_argument("--recompute-user", action="store_true", help="allow default user name to follow the new project name")
  rename.set_defaults(func=cmd_rename)

  args = parser.parse_args(argv)
  args.func(args)

if __name__ == "__main__":
  main(sys.argv[1:])