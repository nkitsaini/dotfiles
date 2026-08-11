{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./capture
    ./k9s
    ./ghostty
  ];
}
