{
  lib,
  pkgs,
  projectCatalogJson,
  userPrefix ? "usr.prj_",
  workDirName ? "src",
  grantRoot,
}:

let
  projectGrantScript = pkgs.writeText "project-grant.py" (builtins.readFile ./project-grant.py);
in
pkgs.writeShellApplication {
  name = "project-grant";
  runtimeInputs = [
    pkgs.acl
    pkgs.python3
  ];
  text = ''
    export PROJECT_CATALOG_JSON=${lib.escapeShellArg projectCatalogJson}
    export PROJECT_USER_PREFIX=${lib.escapeShellArg userPrefix}
    export PROJECT_WORKDIR_NAME=${lib.escapeShellArg workDirName}
    export PROJECT_GRANT_ROOT=${lib.escapeShellArg grantRoot}
    export SETFACL=${pkgs.acl}/bin/setfacl
    exec python3 ${lib.escapeShellArg projectGrantScript} "$@"
  '';
}
