{
  pkgs,
  config,
  lib,
  module_inputs,
  ...
}:

with lib;
let
  cfg = config.kit.services.notes-sync;

  notesDirectory = "${config.home.homeDirectory}/code/notes";
  git_syncer = module_inputs.git_syncer.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.kit.services.notes-sync = {
    enable = mkEnableOption "Enable syncing notes directory";

    repositories = mkOption {
      type = types.listOf types.str;
      default = [notesDirectory];
      description = "Path to repositories to sync";
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
        ExecStart = lib.concatStringsSep " " ([
          "${git_syncer}/bin/git_syncer"
        ] ++ cfg.repositories);
        Restart = "on-failure";
        RuntimeMaxSec = "5h";
      };
    };
  };
}
