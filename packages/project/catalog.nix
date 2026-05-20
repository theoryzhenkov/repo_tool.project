{
  lib,
  pkgs,
  projectCatalogJson,
  userPrefix ? "usr.prj_",
  catalogWriteDir ? "",
  applyMessage ? null,
}:

let
  realmCatalogScript = pkgs.writeText "realm-catalog.py" (builtins.readFile ./realm-catalog.py);
in
pkgs.writeShellApplication {
  name = "realm-catalog";
  runtimeInputs = [ pkgs.python3 ];
  text = ''
    export REALM_CATALOG_JSON=${lib.escapeShellArg projectCatalogJson}
    export REALM_PROJECT_USER_PREFIX=${lib.escapeShellArg userPrefix}
    export REALM_CATALOG_WRITE_DIR=${lib.escapeShellArg catalogWriteDir}
    ${lib.optionalString (
      applyMessage != null
    ) "export REALM_CATALOG_APPLY_MESSAGE=${lib.escapeShellArg applyMessage}"}
    exec python3 ${lib.escapeShellArg realmCatalogScript} "$@"
  '';
}
