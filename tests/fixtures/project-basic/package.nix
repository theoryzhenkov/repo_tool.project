{
  lib,
  pkgs,
  username,
  projectModules,
}:

let
  projectFixtureCatalogJson = pkgs.writeText "project-fixture-catalog.json" (
    builtins.readFile ./catalog.json
  );
  projectFixtureRenderInput = import ./render-input.nix;
  projectFixtureRender = pkgs.callPackage (projectModules + "/render.nix") (
    { inherit lib; } // projectFixtureRenderInput
  );
  projectFixtureCatalogTool = pkgs.callPackage (projectModules + "/catalog.nix") {
    inherit lib pkgs;
    projectCatalogJson = projectFixtureCatalogJson;
    userPrefix = "usr.prj_";
    catalogWriteDir = "";
  };
  projectFixtureApprovalTool = pkgs.callPackage (projectModules + "/approval.nix") {
    inherit lib pkgs;
    projectCatalogJson = projectFixtureCatalogJson;
    userPrefix = "usr.prj_";
    workDirName = "src";
    approvalRoot = "/tmp/project-fixture-approval";
  };
  projectFixtureApprovalsTui = pkgs.callPackage (projectModules + "/approvals-tui.nix") {
    inherit pkgs;
  };
  projectFixtureCli = pkgs.callPackage projectModules {
    inherit lib pkgs;
    inherit (projectFixtureRender)
      projectList
      repoList
      projectCase
      repoCase
      repoProjectCase
      repoPathRecordsJson
      scopeActCase
      ;
    projectCatalogJson = projectFixtureCatalogJson;
    ownerUser = username;
    agentConfigSharingSystemPackageRoot = null;
    projectApprovalTool = projectFixtureApprovalTool;
    projectCatalogTool = projectFixtureCatalogTool;
    projectApprovalsTui = projectFixtureApprovalsTui;
  };
  projectFixtureCompletions = pkgs.callPackage (projectModules + "/completions.nix") {
    inherit lib pkgs;
    projectLookupNames = [
      "alpha"
      "a"
      "beta"
    ];
    repoLookupNames = [
      "repo.alpha"
      "alpha-repo"
    ];
  };
in
pkgs.callPackage (projectModules + "/package.nix") {
  inherit pkgs;
  projectCli = projectFixtureCli;
  projectApprovalsTui = projectFixtureApprovalsTui;
  projectCompletions = projectFixtureCompletions;
}
