{ config, pkgs, ... }:
let
  domain = "headscale.nkit.dev";
  derpPort = 3478;
in
{
  # MIGRATION/BACKUP GUIDE:
  #    Stop headscale on both: sudo systemctl stop headscale
  #    Just copy /var/lib/headscale from one machine to another (while headscale is stopped.)
  #    Fix permissions with:
  # 			sudo chown -R headscale:headscale /var/lib/headscale
  #       sudo chmod 644 /var/lib/headscale/*
  #       sudo chmod 755 /var/lib/headscale/
  #    Modify DNS for headscale.nkit.dev to new host IP (IMPORTANT: for both ipv4 and ipv6)
  #    Setup the "headscale" servers tailscale client again. And set as exit-node
	#      [See On cloud instructions below]
  #    Start headscale on new host
  #
  #    ON clients restart tailscale via systemd or force stop on android (no re-auth required).
  #    sudo systemctl restart tailscale
  #
  #    Test for debugging:
  # 			`xh https://headscale.nkit.dev/health` (see IP with `curl -v` too)

  # ref:
  #  - https://headscale.net/exit-node/
  #  - https://headscale.net/android-client/

  # headscale users create <user>

  # TODO: simplify the below stuff
  # On Cloud:
  #   tailscale up --login-server https://headscale.nkit.dev --ssh --advertise-exit-node
  #   headscale nodes register ... --user <user>
  #   headscale nodes list-routes
  #   headscale routes approve-routes -r "0.0.0.0/0,::/0" -i 1 # Or ID of route from list-routes

  # On Android:
  #   tailscale up --login-server https://headscale.nkit.dev
  #   tailscale exit-node list
  #   tailscale up --login-server https://headscale.nkit.dev --exit-node crane
  #   headscale nodes register ... --user <user>

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
          base_domain = "nkit.home.arpa"; # To avoid random issue, never add a domain that has wildcard entry. (Tailscale -> DNS Search Domain -> Cloudflare)
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
