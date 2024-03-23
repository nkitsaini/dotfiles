{
  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ (import ../../users/kit/username.nix) ];
}
