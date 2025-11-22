{ pkgs, ... }:
{
  home.packages = with pkgs; [ cmus ];
  xdg.configFile."cmus/autosave".source = ./autosave_config;
  xdg.configFile."cmus/autosave".force = true;
}
