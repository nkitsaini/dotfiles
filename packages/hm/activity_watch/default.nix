{ pkgs, ... }:
{

  home.packages = with pkgs; [ activitywatch ];
  services.activitywatch.enable = true;
}
