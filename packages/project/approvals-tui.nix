{
  pkgs,
  makeWrapper,
  title ? "Project approvals",
}:

pkgs.rustPlatform.buildRustPackage {
  pname = "project-approvals-tui";
  version = "0.1.0";
  src = ../project-approvals-tui;
  cargoLock.lockFile = ../project-approvals-tui/Cargo.lock;
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    wrapProgram "$out/bin/project-approvals-tui" \
      --set PROJECT_APPROVALS_TUI_TITLE ${pkgs.lib.escapeShellArg title}
  '';
}
