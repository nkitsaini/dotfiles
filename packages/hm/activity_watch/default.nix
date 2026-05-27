{ pkgs, ... }:
{
  # HM-BUILD-FIX(2026-05-27): disable activitywatch (package + user service)
  # Blocks: ActivityWatch tracker is not installed and the user systemd service is not enabled; no activity logging until re-enabled.
  # Reason: `pkgs.activitywatch` -> `aw-server-rust` -> `aw-webui-0.13.2` builder fails with `Cannot find module 'vue-template-compiler'` during jest tests on the current nixpkgs pin. Upstream packaging regression.
  # Revisit-when: after next `nix flake update` bumps nixpkgs past the fix for aw-webui's jest/vue-template-compiler dependency, or upstream NixOS/nixpkgs ships an aw-webui that builds.
  # home.packages = with pkgs; [ activitywatch ];
  # services.activitywatch.enable = true;
}
