{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./dev-cli
    ./agentic-coding
  ];
}
