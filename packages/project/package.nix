{
  pkgs,
  projectCli,
  projectGrantsTui,
  projectCompletions,
  projectGrantTool ? null,
  projectCatalogTool ? null,
}:

pkgs.symlinkJoin {
  name = "project";
  paths = [
    projectCli
    projectGrantsTui
    projectCompletions
  ]
  ++ pkgs.lib.optionals (projectGrantTool != null) [
    projectGrantTool
  ]
  ++ pkgs.lib.optionals (projectCatalogTool != null) [
    projectCatalogTool
  ];

  # `project` self-elevates through sudo for operations such as
  # `project run`. Sudoers grants the exact aggregate package path
  # `${projectPackage}/bin/project`. If this entry is left as the
  # symlinkJoin-created symlink to the inner CLI derivation, the CLI's
  # `readlink -f "$0"` resolves to that inner path and sudoers rejects it.
  # Keep helper binaries symlinked, but make the public `project` entrypoint
  # a real file owned by this package so canonicalization stays on the path
  # that consumers put in sudoers.
  postBuild = ''
    rm -f "$out/bin/project"
    install -m 0555 ${projectCli}/bin/project "$out/bin/project"
  '';
}
