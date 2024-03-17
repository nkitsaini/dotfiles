{ ... }: {
  imports = [
    ./hardware-configuration.nix
    ./wireguard.nix
    ../../packages/os/ssh.nix

  ];

  nix.settings.experimental-features = ["nix-command" "flakes"];
  documentation.nixos.enable = false; # Takes too much ram causing failures on small machines. https://discourse.nixos.org/t/sudo-nixos-rebuild-switch-does-nothing/9273/14

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "skygod";
  networking.domain = "";
  users.users.root.openssh.authorizedKeys.keys = [(import ./authorized_keys.nix)];

  system.stateVersion = "23.11";
}
