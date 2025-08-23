{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.kit.blocks.dev-cli.k8s;
in
{
  options.kit.blocks.dev-cli.k8s = {
    enable = mkEnableOption "Enable k8s development tools";
  };

  config = mkIf cfg.enable {
    kit.programs.k9s.enable = true;

    home.packages = with pkgs; [
      kubectl
      kubectl-tree
      kubernetes-helm
      kubectx
      tanka
      krew
    ];

    home.sessionPath = [
      "$HOME/.krew/bin"
    ];
  };
}
