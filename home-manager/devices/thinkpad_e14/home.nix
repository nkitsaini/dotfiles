{ ... }:
(let
  username = "ankit";
  homeDirectory = "/home/${username}";
in {
  home.username = username;
  home.homeDirectory = homeDirectory;
  imports = [ ../common_home.nix ../../packages/i3.nix ../../packages/shell ../../packages/wezterm ../../packages/tms ../../packages/helix ];
}
)

