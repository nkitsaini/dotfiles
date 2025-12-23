{
  config,
  lib,
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
        theme = "Gruvbox Light";
        "font-family" = "Noto Sans Mono";
        "font-size" = 14;
        "keybind" = "ctrl+[=esc:";
        minimum-contrast = 1.3;
        bold-color = "bright";
        font-style-bold = false;
        cursor-invert-fg-bg = true;
      };
    };
  };
}
