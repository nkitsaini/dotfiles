{
  pkgs,
  config,
  inputs,
  lib,
  system,
  ...
}:

with lib;
let
  cfg = config.kit.services.notes-sync;

  notesDirectory = "${config.home.homeDirectory}/code/notes";
  git_syncer = inputs.git_syncer.packages.${system}.default;
in
{
  options.kit.services.notes-sync = {
    enable = mkEnableOption "Enable syncing notes directory";

    directory = mkOption {
      type = types.str;
      default = notesDirectory;
      description = "Path to notes directory to sync";
    };
  };

  config = mkIf cfg.enable {
    systemd.user.services.notes-git-sync = {
      Unit = {
        Description = "Periodically syncs notes to git";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };

      Service = {
        ExecStart = "${git_syncer}/bin/git_syncer  --ntfy-channel-file ${notesDirectory}/.ntfy-channel ${notesDirectory}";
        Restart = "on-failure";
        RuntimeMaxSec = "5h";
      };
    };
  };
}
