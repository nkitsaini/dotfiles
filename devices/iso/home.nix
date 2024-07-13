{ ... }:
(let
  username = "nixos";
  homeDirectory = "/home/${username}";
in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../../packages/hm/setup-medium.nix ../../packages/hm/i3.nix ];
})

