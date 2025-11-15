{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./programs
    ./blocks
    ./services
  ];
}
