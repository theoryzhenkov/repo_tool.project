{
  lib,
  pkgs,
  projectModules ? ./.,
  projectModel ? null,
  projectCatalogJson ?
    if projectModel == null then
      throw "projectCatalogJson or projectModel is required"
    else
      builtins.toFile "realm-catalog.json" (builtins.toJSON projectModel.enrichedProjectItems),
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
  grantRoot,
  displayOwner ? ownerUser,
  displayXauthority ? "/home/${ownerUser}/.Xauthority",
  defaultDisplay ? ":0",
  catalogWriteDir ? "",
  catalogApplyMessage ? null,
  agentConfigSharingSystemPackageRoot ? null,
  grantsTuiTitle ? "Realm grants",
  enableGrantsTui ? true,
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
  projectGrantTool = pkgs.callPackage (projectModules + "/grant.nix") {
    inherit
      lib
      pkgs
      projectCatalogJson
      userPrefix
      workDirName
      grantRoot
      displayOwner
      displayXauthority
      defaultDisplay
      ;
  };
  projectGrantsTui =
    if enableGrantsTui then
      pkgs.callPackage (projectModules + "/grants-tui.nix") {
        inherit pkgs;
        title = grantsTuiTitle;
      }
    else
      pkgs.writeShellApplication {
        name = "realm-grants-tui";
        text = ''
          echo "realm-grants-tui: disabled for this package" >&2
          exit 69
        '';
      };
  projectCli = pkgs.callPackage projectModules {
    inherit
      lib
      pkgs
      projectCatalogJson
      ownerUser
      agentConfigSharingSystemPackageRoot
      projectGrantTool
      projectCatalogTool
      projectGrantsTui
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
    projectGrantsTui
    projectCompletions
    projectGrantTool
    projectCatalogTool
    ;
}
