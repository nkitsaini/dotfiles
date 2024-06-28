{ ... }: {
  virtualisation = {
    docker.enable = true;
    # It breaks otherwise as the `127.0.0.11` is never added to /etc/resolv.conf
    # It instead picks the systemd resolv.conf.
    # And also the max 3 dns limit is reacheh
    # TODO: fix this stuff
    docker.extraOptions="--dns=1.1.1.1";
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      # dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };
}
