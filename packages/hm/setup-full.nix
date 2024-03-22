{pkgs, ...}: {
  imports = [./setup-medium.nix];

  home.packages = with pkgs; [
    obs-studio
    evcxr
    brave
    github-desktop
  ];
}
