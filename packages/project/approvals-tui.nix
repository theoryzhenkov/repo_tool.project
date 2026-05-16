{ pkgs }:

pkgs.rustPlatform.buildRustPackage {
  pname = "project-approvals-tui";
  version = "0.1.0";
  src = ../project-approvals-tui;
  cargoLock.lockFile = ../project-approvals-tui/Cargo.lock;
}
