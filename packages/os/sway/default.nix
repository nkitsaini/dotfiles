# This is a nixos package (not home-manager)
{ username, ... }: {

  # Random configuration required to make sway work
  imports = [ ./sway-knobs.nix ];

  home-manager.users.${username} = import ../../hm/sway;
}
