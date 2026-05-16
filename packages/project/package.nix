{
  pkgs,
  projectCli,
  projectApprovalsTui,
  projectCompletions,
  projectApprovalTool ? null,
  projectCatalogTool ? null,
}:

pkgs.symlinkJoin {
  name = "project";
  paths = [
    projectCli
    projectApprovalsTui
    projectCompletions
  ]
  ++ pkgs.lib.optionals (projectApprovalTool != null) [
    projectApprovalTool
  ]
  ++ pkgs.lib.optionals (projectCatalogTool != null) [
    projectCatalogTool
  ];
}
