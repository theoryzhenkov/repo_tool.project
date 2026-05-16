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
  nativeBuildInputs = [ pkgs.makeWrapper ];
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
  postBuild = ''
    rm -f "$out/bin/project"
    makeWrapper ${projectCli}/bin/project "$out/bin/project"
  '';
}
