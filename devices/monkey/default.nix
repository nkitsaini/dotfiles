# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ hostname, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./wireguard.nix

    # sudo nix run github:nix-community/disko --extra-experimental-features flakes --extra=experimental-features nix-command -- --mode disko --flake github:nkitsaini/dotfiles#monkey
    ./disko.nix

    ../../packages/os/core.nix
    ../../packages/os/kernel.nix

    ../../packages/os/podman.nix
    ../../packages/os/virtualbox.nix

    ../../packages/os/ssh.nix

    ../../packages/os/network-desktop.nix
    ../../packages/os/battery.nix
    ../../packages/os/sound.nix
    ../../packages/os/keyboard.nix
    ../../packages/os/fonts.nix

    ../../packages/os/sway

    ../../users/kit
    ../../users/root
  ];

  home-manager.users.${import ../../users/kit/username.nix} = {
    imports = [ ../../packages/hm/setup-full.nix ];
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = hostname; # Define your hostname.

  # Enable CUPS to print documents.
  services.printing.enable = true;
}
