# The core profile is automatically applied to all hosts.
{
  lib,
  pkgs,
  inputs,
  system,
  ...
}: {
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = lib.mkDefault "Asia/Kolkata";

  environment = {
    variables = {DO_NOT_TRACK = "1";};
    systemPackages = with pkgs; [
      binutils
      coreutils
      curl
      dnsutils
      dosfstools
      fd
      git
      tmux
      fish
      neovim
      helix
      htop
      powertop
      iputils
      jq
      # moreutils
      nmap
      sd
      ripgrep
      util-linux # has cfdisk
      whois
      gparted
    ];
  };

  nix = {
    gc.automatic = true;
    optimise.automatic = true;
    settings = {
      cores = 0;
      auto-optimise-store = true;
      allowed-users = ["@wheel"];
      trusted-users = ["root" "@wheel"];
      experimental-features = ["nix-command" "flakes"];
    };
  };

  # better timesync for unstable internet connections
  services.chrony.enable = true;
  services.timesyncd.enable = false;


  # Need to configure home-manager to work with flakes
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = {
    inherit inputs;
    inherit system;
    nixGLCommandPrefix = "";
    disableSwayLock = false;
  };

  nixpkgs.config.allowUnfree = true;

  security.protectKernelImage = true;
  services.earlyoom.enable = true;
  users.mutableUsers = false;

  # For ddcutil
  hardware.i2c.enable = true;

  programs.fuse.userAllowOther = true;

  boot.kernel.sysctl = {
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_queued_events" = 524288;
    "fs.inotify.max_user_instances" = 524288; 
  };

  security.pam.loginLimits = [
  # Increase soft limit for number of open files, default is way too low (~2048)
  {
    domain = "*";        # Applies to all users
    type = "soft";       # Soft limit
    item = "nofile";     # Number of file descriptors
    value = "65535";
  }
  ];


  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "23.11"; # Did you read the comment?
}
