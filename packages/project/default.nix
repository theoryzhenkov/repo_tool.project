{
  lib,
  pkgs,
  projectList,
  repoList,
  projectCase,
  repoCase,
  repoProjectCase,
  projectCatalogJson,
  repoPathRecordsJson,
  scopeActCase,
  ownerUser,
  agentConfigSharingSystemPackageRoot ? null,
  projectGrantTool,
  projectCatalogTool,
  projectGrantsTui,
  sudoCommand ? [
    "/run/wrappers/bin/sudo"
    "-n"
  ],
  switchUserCommand ? [
    "${pkgs.util-linux}/bin/runuser"
    "-u"
  ],
  loginShell ? "${pkgs.fish}/bin/fish",
  sshAgentPath ? "/run/lima-ssh-agent/agent.sock",
  runtimePathPrefix ? [ "/run/wrappers/bin" ],
  projectUserProfileRoot ? "/etc/profiles/per-user",
  runtimePathSuffix ? [
    "/nix/var/nix/profiles/default/bin"
    "/run/current-system/sw/bin"
  ],
}:

pkgs.writeShellApplication {
  name = "realm";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.python3
    pkgs.util-linux
  ];
  text = ''
    # shellcheck disable=SC2016,SC2154,SC2317
    set -eu

    usage() {
      cat <<'USAGE'
    Usage:
      realm list [--project|--repo] [--all|-a] [--here] [--flat] [project]
      realm user [--project|--repo] [--here] <name-or-repo-ref>
      realm path [--project|--repo] [--here] <name-or-repo-ref>
      realm show [--project|--repo] [--here] [--json] <name-or-repo-ref>
      realm enter [--project|--repo] [--here] <name-or-repo-ref> [command...]
      realm run [--project|--repo] [--here] <name-or-repo-ref> <command...>
      realm new <name> [options] [--write]
      realm edit <name> [options] [--write]
      realm rename <old-name> <new-name> [options] [--write]
      realm request access <project> [--mode read|act] [--ttl 1h] [--reason ...]
      realm request sudo -- <command...>
      realm requests
      realm grant show <request-id>
      realm approve <request-id>
      realm reject <request-id>
      realm result <request-id>
      realm logs <request-id>
      realm runs
      realm grants [tui]
      realm revoke <grant-id>
      realm grant list|show|approve|reject|result|logs|runs|revoke|tui [...]
    USAGE
    }

    list_projects_flat() {
      filter_name="''${1:-}"
      python3 - ${lib.escapeShellArg projectCatalogJson} "$filter_name" <<'PY'
    import json, sys
    catalog_path, filter_name = sys.argv[1], sys.argv[2] or None
    with open(catalog_path, "r", encoding="utf-8") as fh:
      catalog = json.load(fh)
    names = sorted(catalog)
    children = {name: [] for name in names}
    def dotted_parent(name):
      parts = name.split(".")
      for i in range(len(parts) - 1, 0, -1):
        candidate = ".".join(parts[:i])
        if candidate in catalog:
          return candidate
      return None
    def parent_for(name):
      parent = dotted_parent(name)
      if parent is not None:
        return parent
      for scope_name in names:
        scope = catalog[scope_name].get("scope", {})
        if name in scope.get("include", []) or (scope.get("includeDescendants") and name.startswith(scope_name + ".")):
          return scope_name
      return None
    for name in names:
      parent = parent_for(name)
      if parent and parent != name:
        children[parent].append(name)
    def label(name):
      aliases = catalog[name].get("aliases", [])
      return name + (f" ({', '.join(aliases)})" if aliases else "")
    def emit_subtree(name):
      print(label(name))
      for child in sorted(children[name]):
        emit_subtree(child)
    if filter_name:
      emit_subtree(filter_name)
    else:
      for name in names:
        print(label(name))
    PY
    }

    list_repos() {
      if [ "$#" -eq 0 ]; then
        cat <<'REPOS'
    ${repoList}
    REPOS
        return 0
      fi
      lookup_project "$1"
      cat <<'REPOS' | awk -F '\t' -v project="$project_name" '$1 == project { print }'
    ${repoList}
    REPOS
    }

    list_tree() {
      include_repos="$1"
      filter_name="''${2:-}"
      python3 - ${lib.escapeShellArg projectCatalogJson} "$include_repos" "$filter_name" <<'PY'
    import json, sys
    catalog_path, include_repos, filter_name = sys.argv[1], sys.argv[2] == "1", sys.argv[3] or None
    with open(catalog_path, "r", encoding="utf-8") as fh:
      catalog = json.load(fh)
    names = sorted(catalog)
    children = {name: [] for name in names}
    roots = []
    def dotted_parent(name):
      parts = name.split(".")
      for i in range(len(parts) - 1, 0, -1):
        candidate = ".".join(parts[:i])
        if candidate in catalog:
          return candidate
      return None
    for name in names:
      parent = dotted_parent(name)
      if parent is None:
        for scope_name in names:
          scope = catalog[scope_name].get("scope", {})
          if name in scope.get("include", []) or (scope.get("includeDescendants") and name.startswith(scope_name + ".")):
            parent = scope_name
            break
      if parent and parent != name:
        children[parent].append(name)
      else:
        roots.append(name)
    def label(name):
      aliases = catalog[name].get("aliases", [])
      return name + (f" ({', '.join(aliases)})" if aliases else "")
    def emit_project(name, depth):
      indent = "  " * depth
      print(indent + label(name))
      if include_repos:
        targets = catalog[name].get("repoTargets", {})
        for repo_name in sorted(targets):
          repo = targets[repo_name]
          if repo.get("synthetic"):
            continue
          aliases = repo.get("aliases", [])
          alias_text = f" aliases={','.join(aliases)}" if aliases else ""
          print(f"{indent}  {repo_name}\t{repo.get('path', "")}{alias_text}")
      for child in sorted(children[name]):
        emit_project(child, depth + 1)
    for root in ([filter_name] if filter_name else sorted(roots)):
      emit_project(root, 0)
    PY
    }

    list_all_flat() {
      filter_name="''${1:-}"
      python3 - ${lib.escapeShellArg projectCatalogJson} "$filter_name" <<'PY'
    import json, sys
    filter_name = sys.argv[2] or None
    with open(sys.argv[1], "r", encoding="utf-8") as fh:
      catalog = json.load(fh)
    names = sorted(catalog)
    children = {name: [] for name in names}
    def dotted_parent(name):
      parts = name.split(".")
      for i in range(len(parts) - 1, 0, -1):
        candidate = ".".join(parts[:i])
        if candidate in catalog:
          return candidate
      return None
    def parent_for(name):
      parent = dotted_parent(name)
      if parent is not None:
        return parent
      for scope_name in names:
        scope = catalog[scope_name].get("scope", {})
        if name in scope.get("include", []) or (scope.get("includeDescendants") and name.startswith(scope_name + ".")):
          return scope_name
      return None
    for name in names:
      parent = parent_for(name)
      if parent and parent != name:
        children[parent].append(name)
    def ordered_subtree(name):
      result = [name]
      for child in sorted(children[name]):
        result.extend(ordered_subtree(child))
      return result
    ordered_names = ordered_subtree(filter_name) if filter_name else names
    for name in ordered_names:
      project = catalog[name]
      aliases = project.get("aliases", [])
      alias_text = f" aliases={','.join(aliases)}" if aliases else ""
      print(f"project\t{name}\t{project.get('user', "")}\t{project.get('workDir', "")}{alias_text}")
      for repo_name, repo in sorted(project.get("repoTargets", {}).items()):
        if repo.get("synthetic"):
          continue
        aliases = repo.get("aliases", [])
        alias_text = f" aliases={','.join(aliases)}" if aliases else ""
        print(f"repo\t{name}\t{repo_name}\t{repo.get('path', "")}{alias_text}")
    PY
    }

    lookup_project() {
      case "''${1:-}" in
    ${projectCase}
        *)
          echo "realm: unknown project: ''${1:-}" >&2
          echo "realm: known projects:" >&2
          list_projects_flat >&2
          exit 64
          ;;
      esac
    }

    lookup_repo() {
      if [ -n "''${REALM_SHELLCHECK_ASSUME_REPOS:-}" ]; then
        repo_project=__shellcheck__
        repo_name=__shellcheck__
        repo_user=__shellcheck__
        repo_home=__shellcheck__
        repo_dir=/__shellcheck__
        return 0
      fi
      case "''${1:-}" in
    ${repoCase}
        *) echo "realm: unknown repo: ''${1:-}" >&2; exit 64 ;;
      esac
    }

    lookup_repo_in_project() {
      project_ref="$1"; repo_ref="$2"; lookup_project "$project_ref"
      case "$project_name:$repo_ref" in
    ${repoProjectCase}
        *) echo "realm: unknown repo in $project_name: $repo_ref" >&2; exit 64 ;;
      esac
    }

    repo_info() {
      repo_ref="$1"; json="''${2:-0}"; lookup_repo "$repo_ref"
      if [ "$json" = 1 ]; then
        python3 - "$repo_project" "$repo_name" ${lib.escapeShellArg projectCatalogJson} <<'PY'
    import json, sys
    project_name, repo_name, catalog_path = sys.argv[1:]
    with open(catalog_path, "r", encoding="utf-8") as fh:
      catalog = json.load(fh)
    print(json.dumps(catalog[project_name]["repoTargets"][repo_name], indent=2, sort_keys=True))
    PY
      else
        printf 'project: %s\nrepo: %s\nuser: %s\nhome: %s\npath: %s\nact-scope: project-user (%s)\n' "$repo_project" "$repo_name" "$repo_user" "$repo_home" "$repo_dir" "$repo_user"
      fi
    }

    project_info() {
      project_ref="$1"; json="''${2:-0}"; lookup_project "$project_ref"
      if [ "$json" = 1 ]; then
        python3 - "$project_name" ${lib.escapeShellArg projectCatalogJson} <<'PY'
    import json, sys
    project_name, catalog_path = sys.argv[1:]
    with open(catalog_path, "r", encoding="utf-8") as fh:
      catalog = json.load(fh)
    print(json.dumps(catalog[project_name], indent=2, sort_keys=True))
    PY
      else
        printf 'project: %s\nuser: %s\nhome: %s\npath: %s\n' "$project_name" "$project_user" "$project_home" "$project_dir"
      fi
    }

    require_root() {
      if [ "$(id -u)" -eq 0 ]; then return 0; fi
      self="$(readlink -f "$0")"
      exec ${lib.escapeShellArgs sudoCommand} "$self" --as-root "$@"
    }

    run_in_current_user_at() { project="$1"; cwd="$2"; shift 2; lookup_project "$project"; cd "$cwd"; exec "$@"; }
    run_in_current_user() { project="$1"; shift; lookup_project "$project"; run_in_current_user_at "$project" "$project_dir" "$@"; }

    caller_can_act_by_scope() {
      case "''${1:-}:''${2:-}" in
    ${scopeActCase}
        *) return 1 ;;
      esac
    }

    require_project_act_grant() {
      project="$1"; lookup_project "$project"; canonical_project="$project_name"; caller="''${SUDO_USER:-}"
      if [ -z "$caller" ] || [ "$caller" = ${lib.escapeShellArg ownerUser} ] || [ "$caller" = "$project_user" ]; then return 0; fi
      if caller_can_act_by_scope "$caller" "$canonical_project"; then return 0; fi
      ${projectGrantTool}/bin/realm-grant can-act "$caller" "$canonical_project" >/dev/null
    }

    run_as_project_at() {
      project="$1"; cwd="$2"; shift 2; lookup_project "$project"
      term="''${TERM:-xterm-256color}"
      path=${lib.escapeShellArg (lib.concatStringsSep ":" runtimePathPrefix)}:${lib.escapeShellArg projectUserProfileRoot}/$project_user/bin:${lib.escapeShellArg (lib.concatStringsSep ":" runtimePathSuffix)}
      extra_env=()
      if ${
        if sshAgentPath == "" then "false" else "true"
      } && [ -S ${lib.escapeShellArg sshAgentPath} ]; then
        extra_env+=(${lib.escapeShellArg "SSH_AUTH_SOCK=${sshAgentPath}"})
      fi
      ${lib.optionalString (agentConfigSharingSystemPackageRoot != null) ''
        extra_env+=(${lib.escapeShellArg "PI_SYSTEM_PACKAGE_ROOT=${agentConfigSharingSystemPackageRoot}"})
      ''}
      exec ${lib.escapeShellArgs switchUserCommand} "$project_user" -- env -i \
        HOME="$project_home" USER="$project_user" LOGNAME="$project_user" SHELL=${lib.escapeShellArg loginShell} \
        PATH="$path" TERM="$term" "''${extra_env[@]}" \
        "${pkgs.bash}/bin/bash" -c "cd \"\$1\"; shift; exec \"\$@\"" realm-run "$cwd" "$@"
    }
    run_as_project() { project="$1"; shift; lookup_project "$project"; run_as_project_at "$project" "$project_dir" "$@"; }

    here_project() {
      cwd="$(pwd -P)"
      python3 - "$cwd" <<'PY'
    import json, sys
    cwd = sys.argv[1].rstrip('/') or '/'
    records = json.loads(${builtins.toJSON repoPathRecordsJson})
    best = None
    for record in records:
      path = record['path'].rstrip('/') or '/'
      if cwd == path or cwd.startswith(path + '/'):
        if best is None or len(path) > len(best['path'].rstrip('/')):
          best = record
    if best is not None: print(best['project'])
    PY
    }
    here_repo() {
      cwd="$(pwd -P)"
      python3 - "$cwd" <<'PY'
    import json, sys
    cwd = sys.argv[1].rstrip('/') or '/'
    records = json.loads(${builtins.toJSON repoPathRecordsJson})
    best = None
    for record in records:
      if record.get('synthetic') or not record.get('repoName'): continue
      path = record['path'].rstrip('/') or '/'
      if cwd == path or cwd.startswith(path + '/'):
        if best is None or len(path) > len(best['path'].rstrip('/')):
          best = record
    if best is not None: print(best['repoName'])
    PY
    }

    parse_list() {
      list_mode=project; list_all=0; list_flat=0; list_here=0; list_filter=""
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --project|-p) list_mode=project ;;
          --repo|-r) list_mode=repo ;;
          --all|-a) list_all=1 ;;
          --flat) list_flat=1 ;;
          --here) list_here=1 ;;
          --*) usage >&2; exit 64 ;;
          *) if [ -n "$list_filter" ]; then usage >&2; exit 64; fi; list_filter="$1" ;;
        esac
        shift
      done
    }

    command="''${1:-}"; as_root=0
    if [ "$command" = "--as-root" ]; then as_root=1; shift; command="''${1:-}"; fi
    if [ -n "$command" ]; then shift; fi

    if [ "$(id -u)" -eq 0 ] && [ -n "''${SUDO_USER:-}" ] && [ "''${SUDO_USER:-}" != ${lib.escapeShellArg ownerUser} ]; then
      case "$command" in
        enter|shell|run) ;;
        ""|help|-h|--help) usage; exit 0 ;;
        *) usage >&2; exit 64 ;;
      esac
    fi

    case "$command" in
      ""|help|-h|--help) usage ;;
      list)
        parse_list "$@"
        if [ "$list_mode" = repo ]; then
          if [ "$list_here" = 1 ]; then list_filter="$(here_project)"; [ -n "$list_filter" ] || { echo "realm: current directory is not inside a known project or repo" >&2; exit 66; }; fi
          if [ -n "$list_filter" ]; then list_repos "$list_filter"; else list_repos; fi
        else
          if [ -n "$list_filter" ]; then lookup_project "$list_filter"; list_filter="$project_name"; fi
          if [ "$list_flat" = 1 ]; then
            if [ "$list_all" = 1 ]; then list_all_flat "$list_filter"; else list_projects_flat "$list_filter"; fi
          else
            list_tree "$list_all" "$list_filter"
          fi
        fi
        ;;
      user|path|show|info)
        target_mode=project; target_here=0; json=0; target_ref=""
        while [ "$#" -gt 0 ]; do
          case "$1" in
            --project|-p) target_mode=project ;;
            --repo|-r) target_mode=repo ;;
            --here) target_here=1 ;;
            --json) json=1 ;;
            --*) usage >&2; exit 64 ;;
            *) if [ -n "$target_ref" ]; then usage >&2; exit 64; fi; target_ref="$1" ;;
          esac
          shift
        done
        if [ "$target_here" = 1 ]; then
          if [ "$target_mode" = repo ]; then target_ref="$(here_repo)"; else target_ref="$(here_project)"; fi
          [ -n "$target_ref" ] || { echo "realm: current directory is not inside a known $target_mode" >&2; exit 66; }
        fi
        [ -n "$target_ref" ] || { usage >&2; exit 64; }
        if [ "$target_mode" = repo ]; then
          lookup_repo "$target_ref"
          case "$command" in user) printf '%s\n' "$repo_user" ;; path) printf '%s\n' "$repo_dir" ;; show|info) repo_info "$target_ref" "$json" ;; esac
        else
          lookup_project "$target_ref"
          case "$command" in user) printf '%s\n' "$project_user" ;; path) printf '%s\n' "$project_dir" ;; show|info) project_info "$target_ref" "$json" ;; esac
        fi
        ;;
      grants)
        subcommand="''${1:-list}"; if [ "$#" -gt 0 ]; then shift; fi
        case "$subcommand" in
          list) if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then require_root grants "$@"; fi; exec ${projectGrantTool}/bin/realm-grant grants "$@" ;;
          tui) exec ${projectGrantsTui}/bin/realm-grants-tui "$@" ;;
          *) usage >&2; exit 64 ;;
        esac
        ;;
      grant)
        subcommand="''${1:-list}"; if [ "$#" -gt 0 ]; then shift; fi
        case "$subcommand" in
          list|requests) if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then require_root requests "$@"; fi; exec ${projectGrantTool}/bin/realm-grant requests "$@" ;;
          show) if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then require_root show "$@"; fi; exec ${projectGrantTool}/bin/realm-grant show "$@" ;;
          approve|reject|revoke) if [ "$as_root" -eq 0 ]; then require_root "$subcommand" "$@"; fi; exec ${projectGrantTool}/bin/realm-grant "$subcommand" "$@" ;;
          result) exec ${projectGrantTool}/bin/realm-grant result "$@" ;;
          logs) exec ${projectGrantTool}/bin/realm-grant logs "$@" ;;
          runs|history) exec ${projectGrantTool}/bin/realm-grant runs "$@" ;;
          tui) exec ${projectGrantsTui}/bin/realm-grants-tui "$@" ;;
          *) usage >&2; exit 64 ;;
        esac
        ;;
      new|edit|rename) exec ${projectCatalogTool}/bin/realm-catalog "$command" "$@" ;;
      request|result|logs|runs) exec ${projectGrantTool}/bin/realm-grant "$command" "$@" ;;
      requests) if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then require_root "$command" "$@"; fi; exec ${projectGrantTool}/bin/realm-grant "$command" "$@" ;;
      approve|reject|revoke|expire-grants) if [ "$as_root" -eq 0 ]; then require_root "$command" "$@"; fi; exec ${projectGrantTool}/bin/realm-grant "$command" "$@" ;;
      enter|shell|run)
        target_mode=project; target_here=0
        while [ "$#" -gt 0 ]; do
          case "$1" in --project|-p) target_mode=project; shift ;; --repo|-r) target_mode=repo; shift ;; --here) target_here=1; shift ;; --*) usage >&2; exit 64 ;; *) break ;; esac
        done
        if [ "$target_here" = 1 ]; then
          cwd="$(pwd -P)"; project="$(here_project)"; [ -n "$project" ] || { echo "realm: current directory is not inside a known project or repo: $cwd" >&2; exit 66; }
          if [ "$#" -eq 0 ]; then set -- ${lib.escapeShellArg loginShell} -l; fi
          lookup_project "$project"
          if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$project_user" ]; then run_in_current_user_at "$project" "$cwd" "$@"; fi
          if [ "$as_root" -eq 0 ]; then require_root "$command" --here "$@"; fi
          require_project_act_grant "$project"; run_as_project_at "$project" "$cwd" "$@"
        fi
        if [ "$#" -lt 1 ]; then usage >&2; exit 64; fi
        target_ref="$1"; shift
        if [ "$command" = run ] && [ "$#" -lt 1 ]; then usage >&2; exit 64; fi
        if [ "$#" -eq 0 ]; then set -- ${lib.escapeShellArg loginShell} -l; fi
        if [ "$target_mode" = repo ]; then
          lookup_repo "$target_ref"
          if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$repo_user" ]; then run_in_current_user_at "$repo_project" "$repo_dir" "$@"; fi
          if [ "$as_root" -eq 0 ]; then require_root "$command" --repo "$target_ref" "$@"; fi
          require_project_act_grant "$repo_project"; run_as_project_at "$repo_project" "$repo_dir" "$@"
        else
          lookup_project "$target_ref"
          if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$project_user" ]; then run_in_current_user "$target_ref" "$@"; fi
          if [ "$as_root" -eq 0 ]; then require_root "$command" --project "$target_ref" "$@"; fi
          require_project_act_grant "$target_ref"; run_as_project "$target_ref" "$@"
        fi
        ;;
      *) usage >&2; exit 64 ;;
    esac
  '';
}
