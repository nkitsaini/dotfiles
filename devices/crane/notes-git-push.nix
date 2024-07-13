{ pkgs, config, ... }:
let
  notesDirectory = "/var/lib/syncthing/notes";
  notesGitPush = pkgs.writeShellApplication {
    name = "notes-git-push";
    runtimeInputs = [ pkgs.nix pkgs.git ];
    text = ''
      cd ${notesDirectory}
      ${pkgs.nix}/bin/nix develop . --command python3 scripts/auto-commit.py
    '';
  };
in {
  systemd.services.notes-git-push = {
    description = "Periodically pushes notes to git";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      ExecStart = "${notesGitPush}/bin/notes-git-push";
      Restart = "on-failure";
      RuntimeMaxSec = "5h";
    };

  };
}
