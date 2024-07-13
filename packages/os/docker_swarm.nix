{ lib, ... }: {
  # See crane/README.md

  # Docker swarm doesn't work with this
  virtualisation.docker.liveRestore = false;

  # Use caddy-l4 plugin to and pass tls as-is to 
  # 9443 after https://github.com/NixOS/nixpkgs/pull/317881
  # services.caddy.virtualHosts = lib.mkAfter {
  #   "http://:80".extraConfig = ''
  #     reverse_proxy 127.0.0.1:9080
  #   '';
  #   "https://:443".extraConfig = ''
  #     reverse_proxy https://127.0.0.1:9443
  #   '';
  # };
}
