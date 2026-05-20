{
  pkgs,
  makeWrapper,
  title ? "Realm grants",
}:

pkgs.rustPlatform.buildRustPackage {
  pname = "realm-grants-tui";
  version = "0.1.0";
  src = ../realm-grants-tui;
  cargoLock.lockFile = ../realm-grants-tui/Cargo.lock;
  nativeBuildInputs = [ makeWrapper ];
  postInstall = ''
    wrapProgram "$out/bin/realm-grants-tui" \
      --set REALM_GRANTS_TUI_TITLE ${pkgs.lib.escapeShellArg title}
  '';
}
