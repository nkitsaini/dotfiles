{ system, config, pkgs, lib, enableNixGL, hyprland, hy3, ... }:
let
  left = "h";
  right = "l";
  up = "k";
  down = "j";
  terminal_cmd = "${pkgs.wezterm}/bin/wezterm";

  bg-color = "#1f242f";
  inactive-bg-color = "#1f242f";
  text-color = "#f3f4f5";
  inactive-text-color = "#676E7D";
  urgent-bg-color = "#E53935";
  nixGLCommandPrefix = if enableNixGL then "nixGL " else "";
  menu =
    "${pkgs.wofi}/bin/wofi -terminal ${terminal_cmd} -show drun -show-icons";
in {
  home.packages = [ pkgs.wofi pkgs.wl-clipboard ];
  
  # modules = [
    # hyprland.homeManagerModules.default
    # {
      wayland.windowManager.hyprland.enable = true;
      # wayland.windowManager.hyprland.plugins = [hy3.packages.${system}.hy3];
      wayland.windowManager.hyprland.plugins = [pkgs.hyprlandPlugins.hy3];
      wayland.windowManager.hyprland.xwayland.enable = true;
      wayland.windowManager.hyprland.systemd.enable = true;
      wayland.windowManager.hyprland.extraConfig =
        builtins.readFile ./hyprland.conf;
    # }
  # ];


  # programs.i3status.enable = true;
  # services.polybar = {
  #   enable = false;
  #   script = "polybar &";
  #   extraConfig = ''
  #   wm-restack = i3
  #   ${builtins.readFile "${pkgs.polybar}/etc/polybar/config.ini"}
  #   '';
  #   # settings = {
  #   #   "bar/bottom" = {
  #   #     height = "3%";
  #   #     width = "100%";
  #   #     modules-right = "volume";
  #   #   };
  #   #   "module/volume" = {
  #   #     type = "internal/pulseaudio";
  #   #     format.volume = "<ramp-volume> <label-volume>";
  #   #     label.muted.text = "🔇";
  #   #     label.muted.foreground = "#666";
  #   #     ramp.volume = [ "🔈" "🔉" "🔊" ];
  #   #     click.right = "pavucontrol &";
  #   #   };
  #   # };
  # };
  # programs.i3blocks = {
  #   enable = false;
  #   bars = {
  #     config = {
  #       time = {
  #         command = "date +%r";
  #         interval = 1;
  #       };
  #       # Make sure this block comes after the time block
  #       date = lib.hm.dag.entryAfter [ "time" ] {
  #         command = "date +%d";
  #         interval = 5;
  #       };
  #       # And this block after the example block
  #       example = lib.hm.dag.entryAfter [ "date" ] {
  #         command = "echo hi $(date +%s)";
  #         interval = 3;
  #       };
  #     };
  #   };
  # };

}
