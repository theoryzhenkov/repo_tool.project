{
  lib,
  pkgs,
  projectModules ? ./.,
  projectModel ? null,
  projectCatalogJson ?
    if projectModel == null then
      throw "projectCatalogJson or projectModel is required"
    else
      builtins.toFile "project-catalog.json" (builtins.toJSON projectModel.enrichedProjectItems),
  projectRecords ? projectModel.projectRecords,
  repoLookupRecords ? projectModel.repoLookupRecords,
  declaredRepoTargetRecords ? projectModel.declaredRepoTargetRecords,
  repoTargetPathRecords ? projectModel.repoTargetPathRecords,
  scopeActRecords ? projectModel.scopeActRecords,
  projectLookupNames ? projectModel.projectLookupNames,
  repoLookupNames ? projectModel.repoLookupNames,
  ownerUser,
  userPrefix ? "usr.prj_",
  workDirName ? "src",
  approvalRoot,
  catalogWriteDir ? "",
  catalogApplyMessage ? null,
  agentConfigSharingSystemPackageRoot ? null,
  approvalsTuiTitle ? "Project approvals",
  sudoCommand ? [
    "/run/wrappers/bin/sudo"
    "-n"
  ],
  switchUserCommand ? [
    "${pkgs.util-linux}/bin/runuser"
    "-u"
  ],
  loginShell ? "${pkgs.fish}/bin/fish",
  sshAgentPath ? "/run/lima-ssh-agent/agent.sock",
  runtimePathPrefix ? [ "/run/wrappers/bin" ],
  projectUserProfileRoot ? "/etc/profiles/per-user",
  runtimePathSuffix ? [
    "/nix/var/nix/profiles/default/bin"
    "/run/current-system/sw/bin"
  ],
}:

let
  projectRender = pkgs.callPackage (projectModules + "/render.nix") {
    inherit
      lib
      projectRecords
      repoLookupRecords
      declaredRepoTargetRecords
      repoTargetPathRecords
      scopeActRecords
      ;
  };
  projectCatalogTool = pkgs.callPackage (projectModules + "/catalog.nix") {
    inherit
      lib
      pkgs
      projectCatalogJson
      userPrefix
      catalogWriteDir
      ;
    applyMessage = catalogApplyMessage;
  };
  projectApprovalTool = pkgs.callPackage (projectModules + "/approval.nix") {
    inherit
      lib
      pkgs
      projectCatalogJson
      userPrefix
      workDirName
      approvalRoot
      ;
  };
  projectApprovalsTui = pkgs.callPackage (projectModules + "/approvals-tui.nix") {
    inherit pkgs;
    title = approvalsTuiTitle;
  };
  projectCli = pkgs.callPackage projectModules {
    inherit
      lib
      pkgs
      projectCatalogJson
      ownerUser
      agentConfigSharingSystemPackageRoot
      projectApprovalTool
      projectCatalogTool
      projectApprovalsTui
      sudoCommand
      switchUserCommand
      loginShell
      sshAgentPath
      runtimePathPrefix
      projectUserProfileRoot
      runtimePathSuffix
      ;
    inherit (projectRender)
      projectList
      repoList
      projectCase
      repoCase
      repoProjectCase
      repoPathRecordsJson
      scopeActCase
      ;
  };
  projectCompletions = pkgs.callPackage (projectModules + "/completions.nix") {
    inherit
      lib
      pkgs
      projectLookupNames
      repoLookupNames
      ;
  };
in
pkgs.callPackage (projectModules + "/package.nix") {
  inherit
    pkgs
    projectCli
    projectApprovalsTui
    projectCompletions
    projectApprovalTool
    projectCatalogTool
    ;
}
