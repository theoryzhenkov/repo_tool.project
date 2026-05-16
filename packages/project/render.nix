{
  lib,
  projectRecords,
  repoLookupRecords,
  declaredRepoTargetRecords,
  repoTargetPathRecords,
  scopeActRecords,
}:

let
  validLookupName = value: builtins.match "[A-Za-z0-9_.-]+" value != null;

  checkedLookupName =
    context: value:
    assert lib.assertMsg (validLookupName value) "project render: invalid ${context}: ${value}";
    value;

  checkedLookupNames = context: values: map (checkedLookupName context) values;

  projectCase = lib.concatMapStringsSep "\n" (
    project:
    let
      patterns = lib.concatStringsSep "|" (
        checkedLookupNames "project name or alias" ([ project.name ] ++ project.aliases)
      );
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
    ${checkedLookupName "repo lookup name" record.lookupName})
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
      projectName = checkedLookupName "repo project name" target.project;
      repoNames = checkedLookupNames "repo name or alias" ([ target.name ] ++ target.aliases);
      patterns = lib.concatStringsSep "|" (map (name: "${projectName}:${name}") repoNames);
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
