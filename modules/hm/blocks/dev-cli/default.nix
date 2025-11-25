{
  config,
  lib,
  pkgs,
  ...
}@inputs:

with lib;

let
  cfg = config.kit.blocks.dev-cli;
in
{
  imports = [
    ./k8s
  ];

  options.kit.blocks.dev-cli = {
    enable = mkEnableOption "Enable all development tools";
  };

  config = mkIf cfg.enable {
    kit.blocks.dev-cli.k8s.enable = true;

    home.packages = with pkgs; [
      # Decode jwts
      jwtinfo

      # Live Serve (with hot-reloading) HTML, CSS etc.
      live-server
    ];
  };
}
