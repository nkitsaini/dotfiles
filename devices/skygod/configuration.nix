{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./wireguard.nix
  ];

  programs.mosh.enable = true;
  nix.settings.experimental-features = ["nix-command" "flakes"];
  documentation.nixos.enable = false; # Takes too much ram causing failures on small machines. https://discourse.nixos.org/t/sudo-nixos-rebuild-switch-does-nothing/9273/14

  networking.firewall.allowPing = true;

  #boot.cleanTmpDir = true;
  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;
  networking.hostName = "skygod";
  networking.domain = "";
  services.openssh.enable = true;
  users.users.root.openssh.authorizedKeys.keys = [(import ./authorized_keys.nix)];
  system.stateVersion = "23.11";
}
