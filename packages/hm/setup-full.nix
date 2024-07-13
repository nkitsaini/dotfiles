{ pkgs, ... }: {
  imports = [ ./setup-medium.nix ./vscode ];

  home.packages = with pkgs; [ obs-studio evcxr brave github-desktop ];
}
