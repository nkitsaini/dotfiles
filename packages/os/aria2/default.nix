let
  port_ranges = [{
    from = 60100;
    to = 60200;
  }];
in {
  # services.aria2 = {
  #   enable = true;
  #   rpcSecretFile = "/root/aria2/rpc_secret.txt";
  #   rpcListenPort = 60001;
  #   openPorts = true;
  #   listenPortRange = port_ranges;

  #   # same as packages/hm/aria2
  #   extraArguments =
  #     "--listen-port=60100-60200  --dht-listen-port=60100-60200 --max-connection-per-server=8 --min-split-size=8M --split=8 --bt-request-peer-speed-limit=10M";

  # };
  networking.firewall = {
    allowedUDPPortRanges = port_ranges;
    allowedTCPPorts = [60001]; # rpc
    allowedTCPPortRanges = port_ranges;
  };

}
