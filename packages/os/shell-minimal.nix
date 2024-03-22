{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    neovim
    tmux
    git
    fish
    helix
  ];
}
