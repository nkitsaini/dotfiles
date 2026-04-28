{
  programs.aria2 = {
    enable = true;
    settings = {
      "listen-port" = "60100-60200";
      "dht-listen-port" = "60100-60200";
      "max-connection-per-server" = "8";
      "min-split-size" = "8M";
      "split" = "8";
      "bt-request-peer-speed-limit" = "10M";
    };
  };
}
