{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.kit.blocks.agentic-coding;
in
{
  options.kit.blocks.agentic-coding = {
    enable = mkEnableOption "agentic coding related tools";
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      antigravity-cli
      code-cursor
      codex
      bubblewrap # sandboxing for codex
    ];
  };
}
