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
  projectApprovalTool,
  projectCatalogTool,
  projectApprovalsTui,
}:

pkgs.writeShellApplication {
  name = "project";
  runtimeInputs = [
    pkgs.coreutils
    pkgs.gawk
    pkgs.python3
    pkgs.util-linux
  ];
  text = ''
    # shellcheck disable=SC2154,SC2317
    set -eu

    usage() {
      cat <<'USAGE'
    Usage:
      project list
      project user <name>
      project path <name>
      project enter <name> [command...]
      project here [command...]
      project run <name> <command...>
      project repo list [project]
      project repo path <repo-ref>
      project repo user <repo-ref>
      project repo show <repo-ref> [--json]
      project repo enter <repo-ref> [command...]
      project new <name> [options] [--write]
      project edit <name> [options] [--write]
      project rename <old-name> <new-name> [options] [--write]
      project request access <name> [--mode read|act] [--ttl 1h] [--reason ...]
      project request sudo -- <command...>
      project requests
      project show <request-id>
      project approve <request-id>
      project reject <request-id>
      project result <request-id>
      project grants
      project revoke <grant-id>
      project approvals
      project approval list|show|approve|reject|result|revoke|tui [...]
      project <name> [command...]
    USAGE
    }

    list_projects() {
      cat <<'PROJECTS'
    ${projectList}
    PROJECTS
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

    lookup_project() {
      case "''${1:-}" in
    ${projectCase}
        *)
          echo "project: unknown project: ''${1:-}" >&2
          echo "project: known projects:" >&2
          list_projects >&2
          exit 64
          ;;
      esac
    }

    lookup_repo() {
      if [ -n "''${PROJECT_SHELLCHECK_ASSUME_REPOS:-}" ]; then
        repo_project=__shellcheck__
        repo_name=__shellcheck__
        repo_user=__shellcheck__
        repo_home=__shellcheck__
        repo_dir=/__shellcheck__
        return 0
      fi
      case "''${1:-}" in
    ${repoCase}
        *)
          echo "project: unknown repo: ''${1:-}" >&2
          exit 64
          ;;
      esac
    }

    lookup_repo_in_project() {
      project_ref="$1"
      repo_ref="$2"
      lookup_project "$project_ref"
      case "$project_name:$repo_ref" in
    ${repoProjectCase}
        *)
          echo "project: unknown repo in $project_name: $repo_ref" >&2
          exit 64
          ;;
      esac
    }

    repo_info() {
      repo_ref="$1"
      json="''${2:-0}"
      lookup_repo "$repo_ref"
      if [ "$json" = 1 ]; then
        python3 - "$repo_project" "$repo_name" ${lib.escapeShellArg projectCatalogJson} <<'PY'
    import json, sys
    project_name, repo_name, catalog_path = sys.argv[1:]
    with open(catalog_path, "r", encoding="utf-8") as fh:
      catalog = json.load(fh)
    target = catalog[project_name]["repoTargets"][repo_name]
    print(json.dumps(target, indent=2, sort_keys=True))
    PY
      else
        printf 'project: %s\nrepo: %s\nuser: %s\nhome: %s\npath: %s\nact-scope: project-user (%s)\n' "$repo_project" "$repo_name" "$repo_user" "$repo_home" "$repo_dir" "$repo_user"
      fi
    }

    require_root() {
      if [ "$(id -u)" -eq 0 ]; then
        return 0
      fi

      self="$(readlink -f "$0")"
      exec /run/wrappers/bin/sudo -n "$self" --as-root "$@"
    }

    run_in_current_user_at() {
      project="$1"
      cwd="$2"
      shift 2
      lookup_project "$project"
      cd "$cwd"
      exec "$@"
    }

    run_in_current_user() {
      project="$1"
      shift
      lookup_project "$project"
      run_in_current_user_at "$project" "$project_dir" "$@"
    }

    caller_can_act_by_scope() {
      case "''${1:-}:''${2:-}" in
    ${scopeActCase}
        *)
          return 1
          ;;
      esac
    }

    require_project_act_grant() {
      project="$1"
      lookup_project "$project"
      canonical_project="$project_name"
      caller="''${SUDO_USER:-}"

      if [ -z "$caller" ] || [ "$caller" = ${lib.escapeShellArg ownerUser} ] || [ "$caller" = "$project_user" ]; then
        return 0
      fi
      if caller_can_act_by_scope "$caller" "$canonical_project"; then
        return 0
      fi

      ${projectApprovalTool}/bin/project-approval can-act "$caller" "$canonical_project" >/dev/null
    }

    run_as_project_at() {
      project="$1"
      cwd="$2"
      shift 2
      lookup_project "$project"

      term="''${TERM:-xterm-256color}"
      path="/run/wrappers/bin:/etc/profiles/per-user/$project_user/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"

      extra_env=()
      if [ -S /run/lima-ssh-agent/agent.sock ]; then
        extra_env+=("SSH_AUTH_SOCK=/run/lima-ssh-agent/agent.sock")
      fi
      ${lib.optionalString (agentConfigSharingSystemPackageRoot != null) ''
        extra_env+=("PI_SYSTEM_PACKAGE_ROOT=${agentConfigSharingSystemPackageRoot}")
      ''}

      # shellcheck disable=SC2016
      exec runuser -u "$project_user" -- env -i \
        HOME="$project_home" \
        USER="$project_user" \
        LOGNAME="$project_user" \
        SHELL="${pkgs.fish}/bin/fish" \
        PATH="$path" \
        TERM="$term" \
        "''${extra_env[@]}" \
        "${pkgs.bash}/bin/bash" -c 'cd "$1"; shift; exec "$@"' project-run "$cwd" "$@"
    }

    run_as_project() {
      project="$1"
      shift
      lookup_project "$project"
      run_as_project_at "$project" "$project_dir" "$@"
    }

    as_root=0
    if [ "''${1:-}" = "--as-root" ]; then
      as_root=1
      shift
    fi

    command="''${1:-}"
    if [ -n "$command" ]; then
      shift
    fi

    if [ "$(id -u)" -eq 0 ] && [ -n "''${SUDO_USER:-}" ] && [ "''${SUDO_USER:-}" != ${lib.escapeShellArg ownerUser} ]; then
      case "$command" in
        enter|shell)
          if [ "$#" -lt 1 ]; then
            usage >&2
            exit 64
          fi
          project="$1"
          shift
          if [ "$#" -eq 0 ]; then
            set -- "${pkgs.fish}/bin/fish" -l
          fi
          require_project_act_grant "$project"
          run_as_project "$project" "$@"
          ;;
        run)
          if [ "$#" -lt 2 ]; then
            usage >&2
            exit 64
          fi
          project="$1"
          shift
          require_project_act_grant "$project"
          run_as_project "$project" "$@"
          ;;
        repo)
          if [ "''${1:-}" != "enter" ] || [ "$#" -lt 2 ]; then
            usage >&2
            exit 64
          fi
          shift
          repo_ref="$1"
          shift
          if [ "$#" -eq 0 ]; then
            set -- "${pkgs.fish}/bin/fish" -l
          fi
          lookup_repo "$repo_ref"
          require_project_act_grant "$repo_project"
          run_as_project_at "$repo_project" "$repo_dir" "$@"
          ;;
        ""|help|-h|--help)
          usage
          ;;
        *)
          project="$command"
          if [ "$#" -eq 0 ]; then
            set -- "${pkgs.fish}/bin/fish" -l
          fi
          require_project_act_grant "$project"
          run_as_project "$project" "$@"
          ;;
      esac
    fi

    case "$command" in
      ""|help|-h|--help)
        usage
        ;;
      list)
        list_projects
        ;;
      user)
        if [ "$#" -ne 1 ]; then
          usage >&2
          exit 64
        fi
        lookup_project "$1"
        printf '%s\n' "$project_user"
        ;;
      path)
        if [ "$#" -ne 1 ]; then
          usage >&2
          exit 64
        fi
        lookup_project "$1"
        printf '%s\n' "$project_dir"
        ;;
      repo)
        subcommand="''${1:-}"
        if [ -n "$subcommand" ]; then
          shift
        fi
        case "$subcommand" in
          list)
            if [ "$#" -gt 1 ]; then
              usage >&2
              exit 64
            fi
            list_repos "$@"
            ;;
          path)
            if [ "$#" -ne 1 ]; then
              usage >&2
              exit 64
            fi
            lookup_repo "$1"
            printf '%s\n' "$repo_dir"
            ;;
          user)
            if [ "$#" -ne 1 ]; then
              usage >&2
              exit 64
            fi
            lookup_repo "$1"
            printf '%s\n' "$repo_user"
            ;;
          show|info)
            json=0
            repo_ref=""
            while [ "$#" -gt 0 ]; do
              case "$1" in
                --json)
                  json=1
                  ;;
                --*)
                  usage >&2
                  exit 64
                  ;;
                *)
                  if [ -n "$repo_ref" ]; then
                    usage >&2
                    exit 64
                  fi
                  repo_ref="$1"
                  ;;
              esac
              shift
            done
            if [ -z "$repo_ref" ]; then
              usage >&2
              exit 64
            fi
            repo_info "$repo_ref" "$json"
            ;;
          enter)
            if [ "$#" -lt 1 ]; then
              usage >&2
              exit 64
            fi
            repo_ref="$1"
            shift
            if [ "$#" -eq 0 ]; then
              set -- "${pkgs.fish}/bin/fish" -l
            fi
            lookup_repo "$repo_ref"
            if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$repo_user" ]; then
              run_in_current_user_at "$repo_project" "$repo_dir" "$@"
            fi
            if [ "$as_root" -eq 0 ]; then
              require_root repo enter "$repo_ref" "$@"
            fi
            require_project_act_grant "$repo_project"
            run_as_project_at "$repo_project" "$repo_dir" "$@"
            ;;
          *)
            usage >&2
            exit 64
            ;;
        esac
        ;;
      approvals)
        exec ${projectApprovalsTui}/bin/project-approvals-tui "$@"
        ;;
      approval)
        subcommand="''${1:-list}"
        if [ "$#" -gt 0 ]; then
          shift
        fi
        case "$subcommand" in
          list|requests)
            if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then
              require_root requests "$@"
            fi
            exec ${projectApprovalTool}/bin/project-approval requests "$@"
            ;;
          show)
            if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then
              require_root show "$@"
            fi
            exec ${projectApprovalTool}/bin/project-approval show "$@"
            ;;
          approve|reject|revoke)
            if [ "$as_root" -eq 0 ]; then
              require_root "$subcommand" "$@"
            fi
            exec ${projectApprovalTool}/bin/project-approval "$subcommand" "$@"
            ;;
          result)
            exec ${projectApprovalTool}/bin/project-approval result "$@"
            ;;
          tui|approvals)
            exec ${projectApprovalsTui}/bin/project-approvals-tui "$@"
            ;;
          *)
            usage >&2
            exit 64
            ;;
        esac
        ;;
      new|edit|rename)
        exec ${projectCatalogTool}/bin/project-catalog "$command" "$@"
        ;;
      request|result)
        exec ${projectApprovalTool}/bin/project-approval "$command" "$@"
        ;;
      requests|show|grants)
        if [ "$as_root" -eq 0 ] && [ "$(id -un)" = ${lib.escapeShellArg ownerUser} ]; then
          require_root "$command" "$@"
        fi
        exec ${projectApprovalTool}/bin/project-approval "$command" "$@"
        ;;
      approve|reject|revoke|expire-grants)
        if [ "$as_root" -eq 0 ]; then
          require_root "$command" "$@"
        fi
        exec ${projectApprovalTool}/bin/project-approval "$command" "$@"
        ;;
      here)
        cwd="$(pwd -P)"
        project="$(python3 - "$cwd" <<'PY'
    import json, sys
    cwd = sys.argv[1].rstrip('/') or '/'
    records = json.loads(${builtins.toJSON repoPathRecordsJson})
    best = None
    for record in records:
      path = record['path'].rstrip('/') or '/'
      if cwd == path or cwd.startswith(path + '/'):
        if best is None or len(path) > len(best['path'].rstrip('/')):
          best = record
    if best is not None:
      print(best['project'])
    PY
        )"
        if [ -z "$project" ]; then
          echo "project: current directory is not inside a known project workdir or repo: $cwd" >&2
          exit 66
        fi
        if [ "$#" -eq 0 ]; then
          set -- "${pkgs.fish}/bin/fish" -l
        fi
        lookup_project "$project"
        if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$project_user" ]; then
          run_in_current_user_at "$project" "$cwd" "$@"
        fi
        if [ "$as_root" -eq 0 ]; then
          # shellcheck disable=SC2016
          require_root enter "$project" ${pkgs.bash}/bin/bash -c 'cd "$1"; shift; exec "$@"' project-here "$cwd" "$@"
        fi
        require_project_act_grant "$project"
        run_as_project_at "$project" "$cwd" "$@"
        ;;
      enter|shell)
        if [ "$#" -lt 1 ]; then
          usage >&2
          exit 64
        fi
        project="$1"
        shift
        if [ "$#" -eq 0 ]; then
          set -- "${pkgs.fish}/bin/fish" -l
        fi
        lookup_project "$project"
        if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$project_user" ]; then
          run_in_current_user "$project" "$@"
        fi
        if [ "$as_root" -eq 0 ]; then
          require_root "$command" "$project" "$@"
        fi
        require_project_act_grant "$project"
        run_as_project "$project" "$@"
        ;;
      run)
        if [ "$#" -lt 2 ]; then
          usage >&2
          exit 64
        fi
        project="$1"
        shift
        lookup_project "$project"
        if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$project_user" ]; then
          run_in_current_user "$project" "$@"
        fi
        if [ "$as_root" -eq 0 ]; then
          require_root "$command" "$project" "$@"
        fi
        require_project_act_grant "$project"
        run_as_project "$project" "$@"
        ;;
      *)
        project="$command"
        if [ "$#" -eq 0 ]; then
          set -- "${pkgs.fish}/bin/fish" -l
        fi
        lookup_project "$project"
        if [ "$as_root" -eq 0 ] && [ "$(id -un)" = "$project_user" ]; then
          run_in_current_user "$project" "$@"
        fi
        if [ "$as_root" -eq 0 ]; then
          require_root enter "$project" "$@"
        fi
        require_project_act_grant "$project"
        run_as_project "$project" "$@"
        ;;
    esac
  '';
}
