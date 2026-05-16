{
  lib,
  projectRecords,
  repoLookupRecords,
  declaredRepoTargetRecords,
  repoTargetPathRecords,
  scopeActRecords,
}:

let
  projectCase = lib.concatMapStringsSep "\n" (
    project:
    let
      patterns = lib.concatStringsSep "|" ([ project.name ] ++ project.aliases);
    in
    ''
      ${patterns})
        project_name=${lib.escapeShellArg project.name}
        project_user=${lib.escapeShellArg project.user}
        project_home=${lib.escapeShellArg project.home}
        project_dir=${lib.escapeShellArg project.entryDir}
        ;;
    ''
  ) projectRecords;

  repoCase = lib.concatMapStringsSep "\n" (record: ''
    ${record.lookupName})
      repo_project=${lib.escapeShellArg record.project}
      repo_name=${lib.escapeShellArg record.name}
      repo_user=${lib.escapeShellArg record.ownerUser}
      repo_home=${lib.escapeShellArg record.home}
      repo_dir=${lib.escapeShellArg record.path}
      ;;
  '') repoLookupRecords;

  repoProjectCase = lib.concatMapStringsSep "\n" (
    target:
    let
      patterns = lib.concatStringsSep "|" (
        map (name: "${target.project}:${name}") ([ target.name ] ++ target.aliases)
      );
    in
    ''
      ${patterns})
        repo_project=${lib.escapeShellArg target.project}
        repo_name=${lib.escapeShellArg target.name}
        repo_user=${lib.escapeShellArg target.ownerUser}
        repo_home=${lib.escapeShellArg target.home}
        repo_dir=${lib.escapeShellArg target.path}
        ;;
    ''
  ) declaredRepoTargetRecords;

  scopeActCase = lib.concatMapStringsSep "\n" (record: ''
    ${lib.escapeShellArg "${record.scopeUser}:${record.targetName}"})
      return 0
      ;;
  '') scopeActRecords;

  projectList = lib.concatMapStringsSep "\n" (
    project:
    if project.aliases == [ ] then
      project.name
    else
      "${project.name} (${lib.concatStringsSep ", " project.aliases})"
  ) projectRecords;

  repoList = lib.concatMapStringsSep "\n" (
    target:
    let
      aliases =
        if target.aliases == [ ] then "" else " aliases=${lib.concatStringsSep "," target.aliases}";
    in
    "${target.project}\t${target.name}\t${target.path}${aliases}"
  ) declaredRepoTargetRecords;
in
{
  inherit
    projectCase
    repoCase
    repoProjectCase
    scopeActCase
    projectList
    repoList
    ;
  repoPathRecordsJson = builtins.toJSON repoTargetPathRecords;
}
