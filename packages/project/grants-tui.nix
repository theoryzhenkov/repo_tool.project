{
  pkgs,
  makeWrapper,
  title ? "Project grants",
}:

pkgs.rustPlatform.buildRustPackage {
  pname = "project-grants-tui";
  version = "0.1.0";
  src = ../project-grants-tui;
  cargoLock.lockFile = ../project-grants-tui/Cargo.lock;
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    wrapProgram "$out/bin/project-grants-tui" \
      --set PROJECT_GRANTS_TUI_TITLE ${pkgs.lib.escapeShellArg title}
  '';
}
