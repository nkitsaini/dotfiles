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
  imports = [ ../common_home.nix ../../packages/i3.nix ];
  home.packages = with pkgs;
    [
      (writeScriptBin "rebuild-system" ''
        #!/usr/bin/env bash
        home-manager switch --flake ${homeDirectory}/code/dotfiles/home-manager#asaini
      '')

    ];
})

