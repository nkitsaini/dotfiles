{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./notes-sync
    ./restic
  ];
}
