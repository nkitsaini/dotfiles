{...}: {
  networking.firewall.allowedTCPPorts = [ 6443 80 443 ];
  networking.firewall.allowedUDPPorts = [ 6443 ];
  services.k3s.enable = true;
}
