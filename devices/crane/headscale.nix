{ config, pkgs, ... }:
let
  domain = "headscale.nkit.dev";
  derpPort = 3478;
in {
  # ref:
  #  - https://headscale.net/exit-node/
  #  - https://headscale.net/android-client/

  # headscale users create <user>

  # TODO: simplify the below stuff
  # On Cloud:
  #   tailscale up --login-server https://headscale.nkit.dev --ssh --advertise-exit-node
  #   headscale nodes register ... --user <user>
  #   headscale routes list
  #   headscale routes enable -r 1 
  #   headscale routes enable -r 2 

  # On Android:
  #   tailscale up --login-server https://headscale.nkit.dev 
  #   tailscale exit-node list
  #   tailscale up --login-server https://headscale.nkit.dev --exit-node crane
  #   headscale nodes register ... --user <user>

  services = {
    headscale = {
      enable = true;
      package =
        (pkgs.runCommand "headscale" { buildInputs = [ pkgs.makeWrapper ]; } ''
          makeWrapper ${pkgs.headscale}/bin/headscale $out/bin/headscale --set HEADSCALE_EXPERIMENTAL_FEATURE_SSH 1
        '');
      address = "0.0.0.0";
      port = 8888;
      settings = {
        acl_policy_path = pkgs.writeTextFile {
          name = "headscale-acl.hujson";
          text = builtins.toJSON {
            acls = [{
              action = "accept";
              src = [ "*" ];
              dst = [ "*:*" ];
            }];
            ssh = [
              {
                action = "accept";
                src = [ "autogroup:member" ];
                dst = [ "autogroup:self" ];
                users = [ "root" "autogroup:nonroot" ];
              }
              {
                action = "accept";
                src = [
                  "*"
                ]; # TODO: fix once headscale 0.23.0 is available on nixos (that finally has non-experimental support for ssh I guess)
                dst = [ "*:*" ];
                users = [ "root" "autogroup:nonroot" "ayush" "*" ];
              }
            ];

          };
        };
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

  networking.firewall.allowedUDPPorts = [ derpPort ];

  environment.etc."sysctl.d/99-tailscale.conf".text = ''
    net.ipv4.ip_forward = 1
    net.ipv6.conf.all.forwarding = 1
  '';
  environment.variables = { HEADSCALE_EXPERIMENTAL_FEATURE_SSH = "1"; };
  environment.sessionVariables = { HEADSCALE_EXPERIMENTAL_FEATURE_SSH = "1"; };

  environment.systemPackages = [ config.services.headscale.package ];
}

