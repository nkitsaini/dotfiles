{pkgs, ...}: {
  imports = [
    ./hardware-configuration.nix
    # TODO: clean the files too
    # ./wireguard.nix
    ./headscale.nix
    ../../packages/os/ssh.nix
    ../../packages/os/tailscale.nix
    ../../packages/os/bluetooth.nix
    ../../packages/os/podman.nix
    ../../packages/os/docker_swarm.nix
    ../../packages/os/syncthing.nix
  ];
  networking.firewall.allowedTCPPorts = [
  80
  443
  9080
  9443
  
  ];


  services.caddy = {
    enable = true;
  };

  nix.settings.experimental-features = ["nix-command" "flakes"];
  documentation.nixos.enable =
    false; # Takes too much ram causing failures on small machines. https://discourse.nixos.org/t/sudo-nixos-rebuild-switch-does-nothing/9273/14

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "crane";
  networking.domain = "";
  users.users.root.openssh.authorizedKeys.keys =
    import ../../packages/authorized_keys.nix;

  system.stateVersion = "23.11";
}
