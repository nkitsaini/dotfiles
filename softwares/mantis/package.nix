{ lib, rustPlatform, runCommand, callPackage, frontend ? callPackage ./frontend.nix { }, git, stdenv }:

let
  source = runCommand "mantis-source" { } ''
    mkdir -p "$out/src" "$out/web"
    cp ${./Cargo.toml} "$out/Cargo.toml"
    cp ${./Cargo.lock} "$out/Cargo.lock"
    cp -r ${./src}/. "$out/src/"
    cp -r ${frontend} "$out/web/build"
  '';
in
rustPlatform.buildRustPackage {
  pname = "mantis";
  version = "0.1.7";
  src = source;
  cargoLock.lockFile = ./Cargo.lock;

  nativeCheckInputs = [ git ];
  doCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;

  meta = {
    description = "Reliable Git synchronization and conflict resolution for Termux";
    homepage = "https://github.com/nkitsaini/dotfiles";
    license = lib.licenses.mit;
    mainProgram = "mantis";
    platforms = lib.platforms.linux;
  };
}
