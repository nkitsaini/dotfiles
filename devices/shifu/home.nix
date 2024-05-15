{ pkgs, ... }:
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
  imports = [ ../../packages/hm/setup-full.nix ../../packages/hm/sway ];
  home.packages = [ pkgs.slack ];
  xdg.mimeApps.associations.added = {
    "x-scheme-handler/slack" = [ "slack.desktop" ];
  };
  targets.genericLinux.enable = true;

  programs.fish.shellAliases.rebuild-system =
    "home-manager switch --flake ${homeDirectory}/code/dotfiles/#shifu";
})

