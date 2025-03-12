{ pkgs, ... }:
(let
  name = "Ankit Saini";
  email = "asaini@singlestore.com";
  username = "asaini";
  homeDirectory = "/home/${username}";
in {
  programs.git.userName = name;
  programs.git.userEmail = email;
  programs.jujutsu.settings.user.name = name;
  programs.jujutsu.settings.user.email = email;
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../../packages/hm/setup-minimal.nix ];
  targets.genericLinux.enable = true;

  programs.fish.shellAliases.rebuild-system =
    "home-manager switch --flake ${homeDirectory}/code/dotfiles/#shifu_remote";
})

