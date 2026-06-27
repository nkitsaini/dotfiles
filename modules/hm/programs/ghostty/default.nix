{
  config,
  lib,
  # Provided as a home-manager specialArg on nixGL hosts (e.g. shifu); defaults
  # to "" elsewhere (NixOS), where GL works natively and no wrapper is needed.
  nixGLCommandPrefix ? "",
  ...
}:

with lib;

let
  cfg = config.kit.programs.ghostty;
in
{
  options.kit.programs.ghostty = {
    enable = mkEnableOption "ghostty terminal";
  };

  config = mkIf cfg.enable {
    programs.ghostty = {
      enable = true;
      settings = {
        theme = "light:Gruvbox Light,dark:Gruvbox Dark";
        "font-family" = "Noto Sans Mono";
        "font-size" = 14;
        "keybind" = "ctrl+[=esc:";
        minimum-contrast = 1.3;
        bold-color = "bright";
        font-style-bold = false;
        cursor-invert-fg-bg = true;
      };
      systemd.enable = true;
    };

    # The systemd/D-Bus-activated ghostty daemon is launched by the user systemd
    # manager, which carries none of the GL driver environment that nixGL injects
    # into the sway session. So a cold start (no running instance -> `+new-window`
    # triggers D-Bus activation -> this service runs bare ghostty) dies with
    # "Unable to acquire OpenGL context for rendering". Interactive launches don't
    # hit this because they inherit the nixGL env from the sway/rofi session.
    # home-manager copies the unit verbatim from the package, so override only the
    # ExecStart via a drop-in, wrapping it in the same nixGL prefix used for
    # sway/rofi. No-op on NixOS (nixGLCommandPrefix == "").
    xdg.configFile."systemd/user/app-com.mitchellh.ghostty.service.d/nixgl.conf" =
      mkIf (nixGLCommandPrefix != "") {
        text = ''
          [Service]
          ExecStart=
          ExecStart=${nixGLCommandPrefix}${getExe config.programs.ghostty.package} --gtk-single-instance=true --initial-window=false
        '';
      };
  };
}
