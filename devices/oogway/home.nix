{ ... }:
(let
  name = "Oogway The Survivor";
  email = "oogway@example.com";
  username = "oogway";
  homeDirectory = "/home/${username}";
in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../../packages/hm/setup-full.nix  ../../packages/hm/sway.nix ];

  # programs.git.userName = name;
  # programs.git.userEmail = email;
  programs.jujutsu.settings.user.name = name;
  programs.jujutsu.settings.user.email = email;
  programs.fish.shellAliases.rebuild-system =
    "sudo nixos-rebuild switch --flake ${homeDirectory}/code/dotfiles/#oogway";
})

