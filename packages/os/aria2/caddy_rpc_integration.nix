{pkgs, ...}: {
  services.caddy = {
    virtualHosts."aria2.nkit.dev".extraConfig = ''
        handle /jsonrpc* {
          reverse_proxy http://localhost:60001
        }
        handle {
            root * ${pkgs.ariang}/share/ariang
            file_server
        }
    '';
  };
}
