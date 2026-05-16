{
  lib,
  pkgs,
  username,
  projectModules,
}:

let
  projectLib = import (projectModules + "/model.nix") { inherit lib; };
  projectModel = projectLib.mkProjectModel {
    items = {
      alpha = {
        aliases = [ "a" ];
        user = "usr.prj_alpha";
        home = "/tmp/project-alpha-home";
        workDir = "/tmp/project-alpha-home/src";
        defaultRepo = "repo.alpha";
        repos."repo.alpha" = {
          aliases = [ "alpha-repo" ];
          path = ".";
          primary = true;
          git.url = "git@example.invalid:alpha.git";
          description = "Alpha repo";
        };
        scope = {
          enable = true;
          include = [ "beta" ];
        };
      };
      beta = {
        user = "usr.prj_beta";
        home = "/tmp/project-beta-home";
        workDir = "/tmp/project-beta-home/src";
      };
    };
  };
in
pkgs.callPackage (projectModules + "/profile.nix") {
  inherit
    lib
    pkgs
    projectModules
    projectModel
    ;
  ownerUser = username;
  userPrefix = "usr.prj_";
  workDirName = "src";
  grantRoot = "/tmp/project-fixture-grants";
  catalogWriteDir = "";
  agentConfigSharingSystemPackageRoot = null;
}
