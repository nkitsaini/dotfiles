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
    fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
  };


  # otherwise blocks nixos-rebuild if wired is unplugged.
  systemd.network.wait-online.enable = false;

  # need to use nmtui and applet from networkmanager
  # need to use dhcp fallback to link-local using systemd
  networking.useNetworkd = true;
  systemd.network.networks."30-wired" = {
    matchConfig = { Type = "ether"; };
    DHCP = "yes";
    networkConfig = {
      IPv6PrivacyExtensions = "yes";
      LinkLocalAddressing ="yes";
      # Address = "192.168.10.2/24";
    };
  };

  #### 90-disable-non-wired seems to be effective in blocking, but just securing both ends.
  systemd.network.networks."10-disable-non-wired" = {
    matchConfig = { Type = "!ether"; };
    linkConfig = {
      Unmanaged = "yes";
    };
  };
  systemd.network.networks."90-disable-non-wired" = {
    matchConfig = { Type = "!ether"; };
    linkConfig = {
      Unmanaged = "yes";
    };
  };

  networking.wireless.enable = false;
  networking.networkmanager = {
    enable = true;
    wifi.backend = "iwd";
    # https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_and_managing_networking/configuring-networkmanager-to-ignore-certain-devices_configuring-and-managing-networking
    unmanaged = ["type:ethernet"];
  };

  networking.wireless.iwd.settings = {
    Network = { NameResolvingService = "systemd"; };
  };
}
