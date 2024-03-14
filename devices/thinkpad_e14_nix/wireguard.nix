# From https://nixos.wiki/wiki/WireGuard
{pkgs, ...}: 
let 
  interface = "enp1s0";
  in { 

  environment.systemPackages = with pkgs; [
    wireguard-tools
  ];
  # enable NAT
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
  };
}
