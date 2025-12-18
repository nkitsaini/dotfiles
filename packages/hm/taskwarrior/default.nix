{ pkgs, ... }:
{
  programs.taskwarrior = {
    enable = true;
    package = pkgs.taskwarrior3;
    colorTheme = "light-256";
    # config = {
    #   color.alternate = "black on bright black";
    # };
  };
  home.packages = [
    pkgs.taskwarrior-tui
  ];
}
