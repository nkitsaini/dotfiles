# This is a nixos package (not home-manager)
{ pkgs, ... }:
let

  left = "h";
  right = "l";
  up = "k";
  down = "j";
  terminal_cmd = "${pkgs.wezterm}/bin/wezterm";

  out_laptop = "eDP-1";
  out_monitor = "HDMI-A-1";

  _touchpad = {
    click_method = "clickfinger";
    tap = "enabled";
    dwt = "enabled"; # disable while typing
    scroll_method = "two_finger";
    natural_scroll = "disabled";
    scroll_factor = "0.75";
    accel_profile = "adaptive";
  };
  _keyboard = {
    xkb_layout = "us";
    # xkb_variant = "colemak_dh";
    repeat_rate = "50";
    repeat_delay = "160";
  };

  username = import ../../../users/kit/username.nix;

  menu =
    "${pkgs.rofi-wayland}/bin/rofi -terminal ${terminal_cmd} -show drun -show-icons";
in {

  # Random configuration required to make sway work
  imports = [ ./sway-knobs.nix ];

  home-manager.users.${username} = import ../../hm/sway;
}
