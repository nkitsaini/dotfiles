# This is a nixos package (not home-manager)
{ ... }:
let
  username = import ../../../users/kit/username.nix;

in {

  # Random configuration required to make sway work
  imports = [ ./sway-knobs.nix ];

  home-manager.users.${username} = import ../../hm/sway;
}
