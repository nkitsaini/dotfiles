{
  pkgs,
  lib,
  config,
  ...
}:
let
  # has l4 plugin
  caddyPackage = pkgs.stdenv.mkDerivation {
    pname = "caddy-with-l4";
    version = "1.0.0";
    src = ./.;
    meta.mainProgram = "caddy";

    nativeBuildInputs = [ pkgs.caddy ];

    installPhase = ''
      mkdir -p $out/
      cp -r ${pkgs.caddy}/lib $out/lib
      cp -r ${pkgs.caddy}/share $out/share
      mkdir -p $out/bin
      cp -r ./caddy $out/bin/caddy
    '';
  };

  host_http_port = "10080";
  host_tls_port = "10443";
  k3s_http_port = "30080";
  k3s_tls_port = "30443";

  # TODO: this should be derived from config.caddy.virtualHosts
  host_services = builtins.attrNames config.services.caddy.virtualHosts;

  host_http_rule = lib.concatStringsSep " || " (map (x: "Host(`${x}`)") host_services);
  host_tls_rule = lib.concatStringsSep " || " (map (x: "HostSNI(`${x}`)") host_services);
in
{
  services.caddy = {
    enable = true;
    package = caddyPackage;
    globalConfig = ''
      http_port ${host_http_port}
      https_port ${host_tls_port}
    '';
  };
  services.traefik = {
    enable = true;
    staticConfigOptions = {
      entryPoints = {
        web = {
          address = ":80";
        };
        websecure = {
          address = ":443";
        };
      };
    };
    dynamicConfigOptions = {
      http = {
        routers = {
          host-http = {
            entryPoints = [ "web" ];
            rule = host_http_rule;
            service = "host-caddy-http";
          };

          k3s-http = {
            entryPoints = [ "web" ];
            rule = "HostRegexp(`.*`)";
            service = "k3s-caddy-http";
          };
        };
        services = {
          host-caddy-http = {
            loadBalancer.servers = [ { url = "http://127.0.0.1:${host_http_port}"; } ];
          };
          k3s-caddy-http = {
            loadBalancer.servers = [ { url = "http://127.0.0.1:${k3s_http_port}"; } ];
          };
        };
      };
      tcp = {
        routers = {
          host-tls = {
            entryPoints = [ "websecure" ];
            rule = host_tls_rule;
            service = "host-caddy-tls";
            tls.passthrough = true;
          };
          k3s-tls = {
            entryPoints = [ "websecure" ];
            rule = "HostSNI(`*`)";
            service = "k3s-caddy-tls";
            tls.passthrough = true;
          };
        };

        services = {
          host-caddy-tls = {
            loadBalancer.servers = [ { address = "127.0.0.1:${host_tls_port}"; } ];
          };
          k3s-caddy-tls = {
            loadBalancer.servers = [ { address = "127.0.0.1:${k3s_tls_port}"; } ];
          };
        };
      };
    };
  };
}
