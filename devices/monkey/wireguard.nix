# From https://nixos.wiki/wiki/WireGuard
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [ wireguard-tools ];
  # enable NAT
  networking.firewall = { allowedUDPPorts = [ 51820 ]; };
}
