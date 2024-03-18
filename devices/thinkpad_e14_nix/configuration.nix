# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ pkgs, ... }:

{
  imports = [ # Include the results of the hardware scan.
    ./hardware-configuration.nix
    ./wireguard.nix
    ../../packages/os/kernel.nix
    ../../packages/os/podman.nix
    ../../packages/os/ssh.nix
    ../../packages/os/battery.nix
    ../../packages/os/sound.nix
    ../../packages/os/keyboard.nix
    ../../packages/os/locale_in.nix
    ../../packages/os/network-desktop.nix
    ../../packages/os/sway-knobs.nix
    ../../packages/os/fonts.nix
    ../../packages/os/shell-minimal.nix
  ];


  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "ankits"; # Define your hostname.

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  networking.useNetworkd = true;
  systemd.network.networks."40-wired" = {
    matchConfig = {Name = pkgs.lib.mkForce "enp* eth*" ;};
    DHCP = "yes";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.ankits = {
    isNormalUser = true;
    description = "Ankit Saini";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
    ]; # "video" is required for brightness control
    packages = with pkgs;
      [
        firefox
        #  thunderbird
      ];
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?

}
