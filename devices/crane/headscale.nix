{
  config,
  ...
}: 
let
  domain = "headscale.nkit.dev";
  derpPort = 3478;
in {
  # ref:
  #  - https://headscale.net/exit-node/
  #  - https://headscale.net/android-client/

  # namespace = head
  # headscale namespaces create <namespace>

  # TODO: simplify the below stuff
  # On Cloud:
  #   tailscale up --login-server https://headscale.nkit.dev --ssh --advertise-exit-node
  #   headscale nodes register ... --user <namespace>
  #   headscale routes list
  #   headscale routes enable -r 1 
  #   headscale routes enable -r 2 

  # On Android:
  #   tailscale up --login-server https://headscale.nkit.dev 
  #   tailscale exit-node list
  #   tailscale up --login-server https://headscale.nkit.dev --exit-node crane
  #   headscale nodes register ... --user <namespace>

  services = {
    headscale = {
      enable = true;
      address = "0.0.0.0";
      port = 8888;
      settings = {
        dns_config = {
          override_local_dns = true;
          nameservers = [ "1.1.1.1" ]; # TODO: and 100.100.100.100?
          base_domain = "nkit.dev";
        };


        ip_prefixes = "100.64.0.0/24";
        # prefixes = {
        #   v4 = "100.64.0.0/24";
        # };
        server_url = "https://${domain}";
        logtail.enabled = false;
        derp.server = {
          enable = true;
          region_id = 999;
          stun_listen_addr = "0.0.0.0:${toString derpPort}";
        };
      };
    };

    caddy.virtualHosts.${domain}.extraConfig = ''
    reverse_proxy http://localhost:${toString config.services.headscale.port}
    '';
  };

  networking.firewall.allowedUDPPorts = [derpPort];

  environment.etc."sysctl.d/99-tailscale.conf".text = ''
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
  '';

  environment.systemPackages = [ config.services.headscale.package ];
}

