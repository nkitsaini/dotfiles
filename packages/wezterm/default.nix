{pkgs, ...}: {
  home.packages = [
    pkgs.glib # to fix cusor issue in hyprland, see ./wezterm.lua
  ];
  programs.wezterm = {
    enable = true;
    extraConfig = ''
      ${builtins.readFile ./wezterm.lua}
    '';
  };

}
