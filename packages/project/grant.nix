{
  lib,
  pkgs,
  projectCatalogJson,
  userPrefix ? "usr.prj_",
  workDirName ? "src",
  grantRoot,
}:

let
  realmGrantScript = pkgs.writeText "realm-grant.py" (builtins.readFile ./realm-grant.py);
in
pkgs.writeShellApplication {
  name = "realm-grant";
  runtimeInputs = [
    pkgs.acl
    pkgs.python3
  ];
  text = ''
    export REALM_CATALOG_JSON=${lib.escapeShellArg projectCatalogJson}
    export REALM_PROJECT_USER_PREFIX=${lib.escapeShellArg userPrefix}
    export REALM_PROJECT_WORKDIR_NAME=${lib.escapeShellArg workDirName}
    export REALM_GRANT_ROOT=${lib.escapeShellArg grantRoot}
    export SETFACL=${pkgs.acl}/bin/setfacl
    exec python3 ${lib.escapeShellArg realmGrantScript} "$@"
  '';
}
