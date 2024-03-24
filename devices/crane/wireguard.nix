# From https://nixos.wiki/wiki/WireGuard
#   mkdir /tmp/wg_generator
#   wg genkey | cat > private.key
#   wg pubkey < private.key > public.key

# [Interface]
# Address = 10.0.0.2/24
# ListenPort = 51820
# PrivateKey = <generated private key>
# 
# 
# [Peer]
# PublicKey = <server public key>
# AllowedIPs = 0.0.0.0/0, ::/0
# Endpoint = <host>:51820


{pkgs, ...}: 
let 
  interface = "enp1s0";
  in { 

  # enable NAT
  networking.nat.enable = true;
  networking.nat.externalInterface = interface;
  networking.nat.internalInterfaces = [ "wg0" ];
  networking.firewall = {
    allowedUDPPorts = [ 51820 ];
  };

  networking.wireguard.interfaces = {
    # "wg0" is the network interface name. You can name the interface arbitrarily.
    wg0 = {
      # Determines the IP address and subnet of the server's end of the tunnel interface.
      ips = [ "10.100.0.1/24" ];

      # The port that WireGuard listens to. Must be accessible by the client.
      listenPort = 51820;

      # This allows the wireguard server to route your traffic to the internet and hence be like a VPN
      # For this to work you have to set the dnsserver IP of your router (or dnsserver of choice) in your clients
      postSetup = ''
        ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s 10.100.0.0/24 -o ${interface} -j MASQUERADE
      '';

      # This undoes the above command
      postShutdown = ''
        ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s 10.100.0.0/24 -o ${interface} -j MASQUERADE
      '';

      # Path to the private key file.
      #
      # Note: The private key can also be included inline via the privateKey option,
      # but this makes the private key world-readable; thus, using privateKeyFile is
      # recommended.
      privateKeyFile = "/root/wireguard/private.key";

      peers = [
        # List of allowed peers.
        {
          # Mobile
          publicKey = "YDw2Eh/SM3yEqET382nLHncQTl9rZfstnrhssH8m4iY=";
          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          allowedIPs = [ "10.100.0.2/32" ];
        }
        {
          # E14
          publicKey = "eHSiKUygfyRlsCZKkYDTiMmOI3BKdKfReMWWRDxksBY=";
          # List of IPs assigned to this peer within the tunnel subnet. Used to configure routing.
          allowedIPs = [ "10.100.0.3/32" ];
        }
      ];
    };
  };
}
