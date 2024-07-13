{ ... }: {
  # This can be moved inside k3s, but more reliable here until kubenix is stable I guess.
  services.dockerRegistry = {
    enable = true;
    listenAddress = "0.0.0.0";
    port = 5000;
    openFirewall = true;
  };
}
