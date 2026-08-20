{ config, pkgs, ... }: {
  home.stateVersion = "23.11";
  home.username = "root";
  home.homeDirectory = "/root";
  programs.home-manager.enable = true;
  programs.git.enable = true;
  programs.git.settings.user.name = "cranekit";
  programs.git.settings.user.email = "cranekit@example.com";
  programs.bash.enable = true;
  programs.neovim.enable = true;
  programs.tmux.enable = true;

  kit.rebuild = {
    enable = true;
    kind = "nixos";
    # Historical attribute name used by this host's rebuild helper.
    attribute = "crane2";
  };
}
