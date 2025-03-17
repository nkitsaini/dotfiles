{ pkgs, config, ... }:
{
  # Let's stick with LTS for a few weeks to see if bluetooth issue persists
  # boot.kernelPackages = pkgs.linuxPackages_latest;
  environment.systemPackages = [
    config.boot.kernelPackages.perf
  ];

}
