# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, hostname, username, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./k3s.nix
    ./docker-registery.nix
    ../../packages/os/core.nix
    ../../packages/os/kernel.nix
    ../../packages/os/podman.nix
    ../../packages/os/ssh.nix
    ../../packages/os/battery.nix
    ../../packages/os/sound.nix
    ../../packages/os/keyboard.nix
    ../../packages/os/locale_in.nix
    ../../packages/os/network-desktop.nix
    ../../packages/os/sway
    ../../packages/os/fonts.nix
    ../../packages/os/tailscale.nix
    ../../users/root
    ../../users/kit
  ];

  home-manager.users.${username} = {
    imports = [ ../../packages/hm/setup-full.nix ];
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 120;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = hostname; # Define your hostname.

  services.logind.lidSwitch = "ignore";
  services.logind.lidSwitchDocked = "ignore";
  services.logind.lidSwitchExternalPower = "ignore";

  # For ddcutil
  hardware.i2c.enable = true;

  # TODO:
  services.openssh = {
    settings = {
      KbdInteractiveAuthentication = pkgs.lib.mkForce false;
      PasswordAuthentication = pkgs.lib.mkForce false;
    };
  };

}
