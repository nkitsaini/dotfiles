{
  config,
  lib,
  ...
}:

with lib;

let
  cfg = config.kit.programs.obs;
in
{
  options.kit.programs.obs = {
    enable = mkEnableOption "Enable obs";
  };

  config = mkIf cfg.enable {
    programs.obs-studio = {
      enable = true;
      enableVirtualCamera = true;
    };
  };
}
