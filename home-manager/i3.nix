{ config, pkgs, lib, ... }:
let
  terminal = "${pkgs.alacritty}/bin/alacritty";
  menu = "${pkgs.rofi}/bin/rofi -terminal ${terminal} -show drun -show-icons";
in {
  xsession.windowManager.i3.enable = true;
  xsession.windowManager.i3.config.terminal = "nixGL alacritty";
  xsession.initExtra = ''
    xset r rate 160 50
  '';
  xsession.windowManager.i3.config.keybindings =
    let modifier = config.xsession.windowManager.i3.config.modifier;
    in lib.mkOptionDefault {
      "${modifier}+h" = "focus left";
      "${modifier}+j" = "focus down";
      "${modifier}+k" = "focus up";
      "${modifier}+l" = "focus right";
      "${modifier}+Shift+h" = "move left";
      "${modifier}+Shift+j" = "move down";
      "${modifier}+Shift+k" = "move up";
      "${modifier}+Shift+l" = "move right";
      "${modifier}+semicolon" = "split h";
      "${modifier}+Shift+e" = "exec 'i3-msg exit'";

      "${modifier}+Return" = "exec nixGL ${terminal}";
      "${modifier}+d" = "exec ${menu}";
    };

}
