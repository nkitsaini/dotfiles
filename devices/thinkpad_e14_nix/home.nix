{ ... }:
(let
  name = "Ankit Saini";
  email = "nnkitsaini@gmail.com";
  username = "ankits";
  homeDirectory = "/home/${username}";
in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../common_home.nix ../../packages/sway.nix ];

  programs.git.userName = name;
  programs.git.userEmail = email;
  programs.jujutsu.settings.user.name = name;
  programs.jujutsu.settings.user.email = email;
  programs.fish.shellAliases.rebuild-system = "sudo nixos-rebuild switch --flake ${homeDirectory}/code/dotfiles/";
}
)

