{
  lib,
  pkgs,
  projectCatalogJson,
  userPrefix ? "usr.prj_",
  catalogWriteDir ? "",
}:

let
  projectCatalogScript = pkgs.writeText "project-catalog.py" (builtins.readFile ./project-catalog.py);
in
pkgs.writeShellApplication {
  name = "project-catalog";
  runtimeInputs = [ pkgs.python3 ];
  text = ''
    export PROJECT_CATALOG_JSON=${lib.escapeShellArg projectCatalogJson}
    export PROJECT_USER_PREFIX=${lib.escapeShellArg userPrefix}
    export PROJECT_CATALOG_WRITE_DIR=${lib.escapeShellArg catalogWriteDir}
    exec python3 ${lib.escapeShellArg projectCatalogScript} "$@"
  '';
}
