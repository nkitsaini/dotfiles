{ lib, ... }: {
  networking.nameservers =
    [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];

  # systemd-resolved instead of dhcpcd
  # TODO: this currently does not work with iwd
  # networking.useDHCP = false;
  # networking.dhcpcd.enable = false;

  services.resolved = {
    enable = true;

    dnssec = "false";
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
  };

  networking.useNetworkd = true;

  # otherwise blocks nixos-rebuild if wired is unplugged.
  systemd.network.wait-online.enable = false;

  systemd.network.networks."40-wired" = {
    matchConfig = { Name = lib.mkForce "enp* eth*"; };
    DHCP = "yes";
    networkConfig = {
      IPv6PrivacyExtensions = "yes";
      Address = "192.168.10.1/24";
    };
  };

  networking.wireless.enable = false;
  networking.wireless.iwd.enable = true;
  networking.wireless.iwd.settings = {
    Network = { NameResolvingService = "systemd"; };
  };
}
