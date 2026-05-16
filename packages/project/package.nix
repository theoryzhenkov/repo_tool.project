{
  pkgs,
  projectCli,
  projectApprovalsTui,
  projectCompletions,
}:

pkgs.symlinkJoin {
  name = "project";
  paths = [
    projectCli
    projectApprovalsTui
    projectCompletions
  ];
}
