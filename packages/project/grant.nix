{
  lib,
  pkgs,
  projectCatalogJson,
  userPrefix ? "usr.prj_",
  workDirName ? "src",
  grantRoot,
  displayOwner ? "",
  displayXauthority ? "",
  defaultDisplay ? ":0",
}:

let
  realmGrantScript = pkgs.writeText "realm-grant.py" (builtins.readFile ./realm-grant.py);
in
pkgs.writeShellApplication {
  name = "realm-grant";
  runtimeInputs = [
    pkgs.acl
    pkgs.python3
    pkgs.xauth
  ];
  text = ''
    export REALM_CATALOG_JSON=${lib.escapeShellArg projectCatalogJson}
    export REALM_PROJECT_USER_PREFIX=${lib.escapeShellArg userPrefix}
    export REALM_PROJECT_WORKDIR_NAME=${lib.escapeShellArg workDirName}
    export REALM_GRANT_ROOT=${lib.escapeShellArg grantRoot}
    export REALM_DISPLAY_OWNER=${lib.escapeShellArg displayOwner}
    export REALM_DISPLAY_XAUTHORITY=${lib.escapeShellArg displayXauthority}
    export REALM_DISPLAY=${lib.escapeShellArg defaultDisplay}
    export SETFACL=${pkgs.acl}/bin/setfacl
    export XAUTH=${pkgs.xauth}/bin/xauth
    exec python3 ${lib.escapeShellArg realmGrantScript} "$@"
  '';
}
