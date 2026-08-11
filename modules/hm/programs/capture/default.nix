{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kit.programs.capture;
  capturePackage = pkgs.writeShellApplication {
    name = "capture";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      export CAPTURE_SESSIONS_DIRECTORY=${lib.escapeShellArg cfg.sessionsDirectory}
      exec python3 ${./capture.py} "$@"
    '';
  };
in
{
  options.kit.programs.capture = {
    enable = lib.mkEnableOption "instant note capture and review";

    sessionsDirectory = lib.mkOption {
      type = lib.types.str;
      description = "Directory in which capture session directories are stored";
    };

    shortcut = lib.mkOption {
      type = lib.types.str;
      default = "Mod4+n";
      description = "Sway keybinding used to open a capture";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ capturePackage ];

    wayland.windowManager.sway.config.keybindings = lib.mkIf config.wayland.windowManager.sway.enable {
      "${cfg.shortcut}" = "exec ${capturePackage}/bin/capture";
    };
  };
}
