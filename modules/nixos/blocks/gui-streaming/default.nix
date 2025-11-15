{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.kit.blocks.gui-streaming;
in
{
  options.kit.blocks.gui-streaming = {
    enable = mkEnableOption "Enable streaming tools (OBS)";
  };

  config = mkIf cfg.enable {
    kit.programs.obs.enable = true;
  };
}
