# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ hostname, pkgs, username, ... }: {
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./wireguard.nix

    # sudo nix run github:nix-community/disko --extra-experimental-features flakes --extra=experimental-features nix-command -- --mode disko --flake github:nkitsaini/dotfiles#monkey
    ./disko.nix

    ../../packages/os/core.nix
    ../../packages/os/kernel.nix
    ../../packages/os/fhs_tools.nix

    ../../packages/os/tailscale.nix

    ../../packages/os/podman.nix
    ../../packages/os/virtualbox.nix

    ../../packages/os/ssh.nix

    ../../packages/os/network-desktop.nix
    ../../packages/os/bluetooth.nix
    ../../packages/os/battery.nix
    ../../packages/os/sound.nix
    ../../packages/os/keyboard.nix
    ../../packages/os/fonts.nix

    ../../packages/os/sway
    ../../packages/os/aria2
    ../../packages/os/games.nix

    ../../users/kit
    ../../users/root
  ];

  home-manager.users.${username} = {
    imports = [ ../../packages/hm/setup-full.nix ];
  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = hostname; # Define your hostname.

  environment.systemPackages = [ pkgs.cups-filters ];

  # Enable CUPS to print documents.
  services.printing.enable = true;
  services.gvfs = { enable = true; };
  services.printing.drivers = [
    pkgs.gutenprint # — Drivers for many different printers from many different vendors.
    pkgs.gutenprintBin # — Additional, binary-only drivers for some printers.
    # pkgs.hplip # — Drivers for HP printers.
    pkgs.hplipWithPlugin # — Drivers for HP printers, with the proprietary plugin. Use NIXPKGS_ALLOW_UNFREE=1 nix-shell -p hplipWithPlugin --run 'sudo -E hp-setup' to add the printer, regular CUPS UI doesn't seem to work.
    pkgs.postscript-lexmark # — Postscript drivers for Lexmark
    pkgs.samsung-unified-linux-driver # — Proprietary Samsung Drivers
    pkgs.splix # — Drivers for printers supporting SPL (Samsung Printer Language).
    pkgs.brlaser # — Drivers for some Brother printers
    pkgs.brgenml1lpr # — Generic drivers for more Brother printers [1]
    pkgs.brgenml1cupswrapper # — Generic drivers for more Brother printers [1]
    pkgs.cnijfilter2 # — Drivers for some Canon Pixma devices (Proprietary driver)
  ];
}
