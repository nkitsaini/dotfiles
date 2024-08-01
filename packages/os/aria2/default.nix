let
  port_ranges = [{
    from = 60100;
    to = 60200;
  }];
in {
  networking.firewall = {
    allowedUDPPortRanges = port_ranges;
    allowedTCPPortRanges = port_ranges;
  };
}
