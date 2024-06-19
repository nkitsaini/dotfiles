{
  # See crane/README.md

  # Docker swarm doesn't work with this
  virtualisation.docker.liveRestore = false;
  services.caddy.virtualHosts = {
    ":80".extraConfig = ''
      reverse_proxy localhost:9080
    '';
    ":443".extraConfig = ''
      reverse_proxy localhost:9443
    '';
  };
}
