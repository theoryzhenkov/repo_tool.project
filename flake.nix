{
  description = "Realm workspace helper CLI package factories";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = lib.genAttrs systems;
      username = "owner";
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          projectFixture = import ./tests/fixtures/project-basic/package.nix {
            inherit lib pkgs username;
            projectModules = ./packages/project;
          };
        in
        {
          realm-fixture = projectFixture;
          default = projectFixture;
        }
      );
      lib = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          projectModelLib = import ./packages/project/model.nix { inherit lib; };
        in
        projectModelLib
        // {
          mkProjectPackage = args: pkgs.callPackage ./packages/project/profile.nix args;
        }
      );
      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
