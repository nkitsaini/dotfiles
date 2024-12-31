{ pkgs, ... }:
{
  programs.taskwarrior = {
    enable = true;
    package = pkgs.taskwarrior3;
    colorTheme = "solarized-light-256";
    # config = {
    #   color.alternate = "black on bright black";
    # };
  };
}
