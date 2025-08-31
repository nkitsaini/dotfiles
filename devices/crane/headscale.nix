{ config, pkgs, ... }:
let
  domain = "headscale.nkit.dev";
  derpPort = 3478;
in
{
	# NOTE: This is deprecated. See crane2/headscale
  services = {
    headscale = {
      enable = true;
      package = (
        pkgs.runCommand "headscale" { buildInputs = [ pkgs.makeWrapper ]; } ''
          makeWrapper ${pkgs.headscale}/bin/headscale $out/bin/headscale --set HEADSCALE_EXPERIMENTAL_FEATURE_SSH 1
        ''
      );
      address = "0.0.0.0";
      port = 8888;

      settings = {

        policy = {
          path = pkgs.writeTextFile {
            name = "headscale-acl.hujson";
            text = builtins.toJSON {
              acls = [
                {
                  action = "accept";
                  src = [ "*" ];
                  dst = [ "*:*" ];
                }
              ];
              ssh = [
                {
                  action = "accept";
                  users = [
                    "kit"
                  ];
                }
              ];

            };
          };
        };
        dns = {
          override_local_dns = true;
          nameservers.global = [ "1.1.1.1" ]; # TODO: and 100.100.100.100?
          base_domain = "hs.nkit.dev";
        };
        # ip_prefixes = "100.64.0.0/24";
        # prefixes = {
        #   v4 = "100.64.3.0/24";
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

  networking.firewall.allowedUDPPorts = [ derpPort ];

  environment.etc."sysctl.d/99-tailscale.conf".text = ''
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
  '';
  environment.variables = {
    HEADSCALE_EXPERIMENTAL_FEATURE_SSH = "1";
  };
  environment.sessionVariables = {
    HEADSCALE_EXPERIMENTAL_FEATURE_SSH = "1";
  };

  environment.systemPackages = [ config.services.headscale.package ];
}
