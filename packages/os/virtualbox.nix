{username, ...}: {
  # re-enable after: https://github.com/NixOS/nixpkgs/pull/311362 & https://github.com/NixOS/nixpkgs/pull/303790
  # context: https://github.com/NixOS/nixpkgs/issues/312336#issuecomment-2125748070 (virtualbox and kernel version mismatch)
  virtualisation.virtualbox.host.enable = false;
  users.extraGroups.vboxusers.members = [ username ];
}
