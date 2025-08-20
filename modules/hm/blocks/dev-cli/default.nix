{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.kit.blocks.dev-cli;
in
{
  options.kit.blocks.dev-cli = {
    enable = mkEnableOption "Enable development tools";
  };

  config = mkIf cfg.enable {
    kit.programs.k9s.enable = true;

    home.packages = with pkgs; [
      # Decode jwts
      jwtinfo
    ];
  };
}
