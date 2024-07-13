{ pkgs, config, ... }:
let
  notesDirectory = "${config.home.homeDirectory}/code/notes";
  notesGitPush = (pkgs.writeShellApplication {
    name = "notes-git-push";
    runtimeInputs = [ pkgs.nix pkgs.git ];
    text = ''
      cd ${notesDirectory}
      ${pkgs.nix}/bin/nix develop . --command python3 -u scripts/auto-commit.py
    '';
  });
in {
  systemd.user.services.notes-git-push = {
    Unit = { Description = "Periodically pushes notes to git"; };
    Install = { WantedBy = [ "default.target" ]; };
    Service = {
      ExecStart = "${notesGitPush}/bin/notes-git-push";
      Restart = "on-failure";
      RuntimeMaxSec = "5h";
    };
  };
}
