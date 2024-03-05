{ ... }:
(let
  name = "Ankit Saini";
  email = "asaini@singlestore.com";
  username = "ankits";
  homeDirectory = "/home/${username}";
in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../common_home.nix ];

  programs.git.userName = name;
  programs.git.userEmail = email;
  programs.fish.shellAliases.rebuild-system = "sudo nixos-rebuild switch --flake /home/ankits/code/dotfiles/home-manager/";
}
)

