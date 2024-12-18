{
  pkgs,
  hostname,
  username,
  ...
}:
{
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
    ../../packages/os/caddy
    ../../packages/os/aria2
    ../../packages/os/aria2/caddy_rpc_integration.nix

    ./headscale.nix
    ./docker-registry.nix
    ../../users/${username}
    ../../users/root
  ];

  home-manager.users.${username} = {
    imports =
      [ ../../packages/hm/setup-minimal.nix ../../packages/hm/notes-git-push ../../packages/hm/aria2/rpc-service.nix ];
  };

  networking.firewall.allowedTCPPorts = [ 80 443 9080 9443 ];

  boot.loader.grub = {
    enable = true;
    # efiSupport = true;
    # efiInstallAsRemovable = true;
    # device = "/dev/sda";
  };
  # boot.loader.efi.efiSysMountPoint = "/boot/efi";

  # boot.loader.grub.enable = true;
  # boot.loader.efi.canTouchEfiVariables = true;

  documentation.nixos.enable = false; # Takes too much ram causing failures on small machines. https://discourse.nixos.org/t/sudo-nixos-rebuild-switch-does-nothing/9273/14

  boot.tmp.cleanOnBoot = true;
  # zramSwap.enable = true;
  networking.hostName = hostname; # Define your hostname.
}
