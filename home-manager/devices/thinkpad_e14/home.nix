{ ... }:
(let
  username = "ankit";
  homeDirectory = "/home/${username}";
in {
  home.username = username;
  home.homeDirectory = homeDirectory;

  imports = [ ../common_home.nix ];
})

