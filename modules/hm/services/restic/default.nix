{
  pkgs,
  config,
  lib,
  module_inputs,
  ...
}:

with lib;
let
  cfg = config.kit.services.restic;

  # At ~/.secrets/restic-password
  password_file = "${config.home.homeDirectory}/.secrets/restic-password";
  backup_repository = "sftp:box-interactive:/home/backups/monkey/restic/";

in
{

  imports = [
    ./restic.nix
  ];
  options.kit.services.restic = {
    enable = mkEnableOption "Enable restic backup";

    repository = mkOption {
      type = types.str;
      default = backup_repository;
      description = "Path to backup repository";
    };

    passwordFile = mkOption {
      type = types.str;
      default = password_file;
      description = "Path to restic password file";
    };
  };

  config = mkIf cfg.enable {
    # use services.restic-kit defined by use as the home-manager restic module uses
    # `PrivateTmp=true` in systemd service which causes a permission issue with ssh config file.
    #  ^ This one took a long time to figure out.
    services.restic-kit = {
      enable = true;
      backups = {

        # restic-localbackup command to see snapshots etc.
        localbackup = {

          passwordFile = cfg.passwordFile;
          repository = cfg.repository;
          extraBackupArgs = [
            "--exclude-file=${./excludes.txt}"
            "--exclude-caches"
          ];
          progressFps = 0.016666; # every 1 minute
          paths = [
            config.home.homeDirectory
          ];
          pruneOpts = [
            "--keep-daily 7"
            "--keep-weekly 4"
            "--keep-monthly 6"
            "--keep-yearly 20"
          ];
          timerConfig = {
            OnCalendar = "daily";
            Persistent = true;
          };
        };
      };
    };
  };
}
