# monitorctl: one CLI for every attached display's settings.
#
# - Laptop panel (eDP-*): kernel backlight via brightnessctl.
# - External monitors: DDC/CI via ddcutil. Generic: works with any
#   DDC/CI-capable monitor on any connector, nothing is hardcoded.
#
# `monitorctl brightness up|down` acts on the sway output the cursor is on;
# the XF86MonBrightness keys are bound to it in ../sway.
#
# Needs read/write access to /dev/i2c-*:
# - NixOS hosts: hardware.i2c.enable (packages/os/core.nix) + "i2c" in
#   extraGroups (users/kit/default.nix).
# - Ubuntu host (shifu): manual setup, see devices/shifu/README.md.
{
  writeShellApplication,
  sway,
  jq,
  ddcutil,
  brightnessctl,
  gawk,
  coreutils,
  util-linux,
}:
writeShellApplication {
  name = "monitorctl";
  runtimeInputs = [
    sway
    jq
    ddcutil
    brightnessctl
    gawk
    coreutils
    util-linux # flock
  ];
  text = builtins.readFile ./monitorctl.sh;
}
