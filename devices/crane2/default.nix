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

  # TODO: This is bad code. I need to refactor user handling.
  # The refactoring is is blocked on modules refactor in "modules/" folder.
  users.users.${username}.hashedPassword =
    pkgs.lib.mkForce "$6$Pi4RhszjfUMHGAGc$uhXuc2lC0/LJevFwZW6dbSHgvGmw596HbNwVvi9.CUl8Z0SoWNezkcgoS5M9HBM.9R52qQVZwRIE4CbHeNHEY.";

  home-manager.users.${username} = {
    imports = [
      ../../packages/hm/setup-minimal.nix
      ../../packages/hm/aria2/rpc-service.nix
    ];
  };

  kit.services.k3s.enable = true;

  networking.firewall.allowedTCPPorts = [
    80
    443
    9080
    9443
  ];

  systemd.network.networks."20-wan" = {
    matchConfig.Name = "enp1s0"; # either ens3 or enp1s0, check 'ip addr'
    networkConfig = {
      IPv6PrivacyExtensions = "yes";
      DHCP = "ipv4";
    };
    address = [
      # replace this subnet with the one assigned to your instance
      "2a01:4f8:1c1c:d4da::1/64" # TODO: move this elsewhere
    ];
    routes = [
      { Gateway = "fe80::1"; }
    ];
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

  documentation.nixos.enable = false; # Takes too much ram causing failures on small machines. https://discourse.nixos.org/t/sudo-nixos-rebuild-switch-does-nothing/9273/14

  boot.tmp.cleanOnBoot = true;
  # zramSwap.enable = true;
  networking.hostName = hostname; # Define your hostname.
}
