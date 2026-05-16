{
  description = "TheoR Nebula project helper CLI package factories";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
      forAllSystems = lib.genAttrs systems;
      username = "theor";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
          projectFixture = import ./tests/fixtures/project-basic/package.nix {
            inherit lib pkgs username;
            projectModules = ./packages/project;
          };
        in {
          project-fixture = projectFixture;
          default = projectFixture;
        });
      formatter = forAllSystems (system: (import nixpkgs { inherit system; }).nixfmt);
    };
}
