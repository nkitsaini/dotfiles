{ ... }:
(let
  name = "Ankit Saini";
  email = "asaini@singlestore.com";
  username = "asaini";
  homeDirectory = "/home/${username}";
in {
  programs.git.userName = name;
  programs.git.userEmail = email;
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../../packages/hm/setup-full.nix ../../packages/hm/i3.nix ];

  programs.fish.shellAliases.rebuild-system =
    "sudo nixos-rebuild switch --flake ${homeDirectory}/code/dotfiles/#shifu";
})

