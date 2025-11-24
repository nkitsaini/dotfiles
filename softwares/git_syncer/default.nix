{
  bun2nix,
  pkgs,
  stdenv,
  ...
}:

let
  gitSyncerApp = bun2nix.mkDerivation {
    packageJson = ./package.json;

    src = ./.;

    bunDeps = bun2nix.fetchBunDeps {
      bunNix = ./bun.nix;
    };
  };
in
stdenv.mkDerivation {
  name = "git_syncer";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/bin
    makeWrapper ${gitSyncerApp}/bin/git_syncer $out/bin/git_syncer \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.git
          pkgs.libnotify
          pkgs.openssh
        ]
      }
  '';

  nativeBuildInputs = [ pkgs.makeWrapper ];

  meta = {
    description = "Git syncer with git binary available";
  };
}
