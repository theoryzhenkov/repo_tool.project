{
  lib,
  pkgs,
  projectCatalogJson,
  userPrefix ? "usr.prj_",
  workDirName ? "src",
  approvalRoot,
}:

let
  projectApprovalScript = pkgs.writeText "project-approval.py" (
    builtins.readFile ./project-approval.py
  );
in
pkgs.writeShellApplication {
  name = "project-approval";
  runtimeInputs = [
    pkgs.acl
    pkgs.python3
  ];
  text = ''
    export PROJECT_CATALOG_JSON=${lib.escapeShellArg projectCatalogJson}
    export PROJECT_USER_PREFIX=${lib.escapeShellArg userPrefix}
    export PROJECT_WORKDIR_NAME=${lib.escapeShellArg workDirName}
    export PROJECT_APPROVAL_ROOT=${lib.escapeShellArg approvalRoot}
    export SETFACL=${pkgs.acl}/bin/setfacl
    exec python3 ${lib.escapeShellArg projectApprovalScript} "$@"
  '';
}
