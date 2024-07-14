{ ... }: {
  programs.mosh.enable = true;
  environment.variables = { MOSH_SERVER_NETWORK_TMOUT = 3600 * 24 * 7; };
}
