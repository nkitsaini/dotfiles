{ pkgs, ... }: {
  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = pkgs.lib.mkDefault false;
      PasswordAuthentication = pkgs.lib.mkDefault false;
    };
  };
  programs.mosh.enable = true;
}
