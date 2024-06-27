{pkgs, hostname, username, ...}: {
  imports = [
    ./hardware-configuration.nix
    # TODO: clean the files too
    # ./wireguard.nix
    ./disco.nix

    ../../packages/os/core.nix
    ../../packages/os/kernel.nix
    ../../packages/os/fhs_tools.nix

    ../../packages/os/tailscale.nix

    ../../packages/os/podman.nix

    ../../packages/os/ssh.nix

    ../../packages/os/network-desktop.nix

    ../../packages/os/docker_swarm.nix
    
    ./headscale.nix
    ./notes-git-push.nix
    ../../users/${username}
    ../../users/root
  ];

  home-manager.users.${username} = {
    home.stateVersion = "23.11";
  };

  networking.firewall.allowedTCPPorts = [
    80
    443
    9080
    9443
  ];

  services.caddy = {
    enable = true;
  };

  boot.loader.grub = {
    enable = true;
    # efiSupport = true;
    # efiInstallAsRemovable = true;
    # device = "/dev/sda";
  };
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # boot.loader.grub.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;


  documentation.nixos.enable =
    false; # Takes too much ram causing failures on small machines. https://discourse.nixos.org/t/sudo-nixos-rebuild-switch-does-nothing/9273/14

  boot.tmp.cleanOnBoot = true;
  # zramSwap.enable = true;
  networking.hostName = hostname; # Define your hostname.
}
