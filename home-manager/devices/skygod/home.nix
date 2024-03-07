{ pkgs, ... }: {
  home.stateVersion = "23.11";
  nixpkgs.config.allowUnfree = true;
  home.username = "root";
  home.homeDirectory = "/root";
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.bash.enable = true;
  programs.neovim.enable = true;
  programs.tmux.enable = true;
  home.packages = with pkgs;
    [
      (writeScriptBin "rebuild-system" ''
        #!/usr/bin/env bash
        sudo nixos-rebuild switch --flake /root/code/dotfiles/home-manager#skygod
      '')

    ];

}
