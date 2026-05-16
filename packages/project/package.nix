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
}
