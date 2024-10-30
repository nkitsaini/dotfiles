{ ... }: {
  networking.firewall.allowedTCPPorts = [ 51413 ];
  networking.firewall.allowedUDPPorts = [ 51413 ];
}
