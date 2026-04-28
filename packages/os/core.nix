# The core profile is automatically applied to all hosts.
{
  lib,
  pkgs,
  inputs,
  system,
  ...
}:
{
  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = lib.mkDefault "Asia/Kolkata";

  environment = {
    variables = {
      DO_NOT_TRACK = "1";

      # Required for cloudflare wrangler
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    };
    systemPackages =
      ((import ../shared/core_deps.nix) pkgs)
      ++ (with pkgs; [
        helix
        tmux
        git
        fish
        neovim
        ripgrep
      ]);
  };

  # Replace the default nix GC with a smarter version that always preserves
  # a minimum number of generations regardless of age.
  nix = {
    gc.automatic = false;
    optimise.automatic = true;
    settings = {
      cores = 0;
      auto-optimise-store = true;
      allowed-users = [ "@wheel" ];
      trusted-users = [
        "root"
        "@wheel"
      ];
      experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
  };

  systemd.services.nix-gc-safe = {
    description = "Nix Garbage Collection (preserves minimum generations)";
    script = ''
      set -euo pipefail

      min_keep=7
      max_days=30
      cutoff_date=$(date -d "$max_days days ago" +%Y-%m-%d)

      delete_old_generations() {
        local profile="$1"

        if [ ! -e "$profile" ]; then
          return
        fi

        local count=0
        local to_delete=()

        while IFS= read -r line; do
          [ -z "$line" ] && continue

          count=$((count + 1))

          if [ "$count" -le "$min_keep" ]; then
            continue
          fi

          local gen_num gen_date
          gen_num=$(echo "$line" | awk '{print $1}')
          gen_date=$(echo "$line" | awk '{print $2}')

          if [[ "$gen_date" < "$cutoff_date" || "$gen_date" == "$cutoff_date" ]]; then
            to_delete+=("$gen_num")
          fi
        done < <(nix-env -p "$profile" --list-generations | sort -rn)

        if [ ''${#to_delete[@]} -gt 0 ]; then
          echo "Deleting ''${#to_delete[@]} old generations from $profile"
          nix-env -p "$profile" --delete-generations ''${to_delete[@]}
        else
          echo "No old generations to delete from $profile"
        fi
      }

      delete_old_generations /nix/var/nix/profiles/system

      for profile_dir in /nix/var/nix/profiles/per-user/*/; do
        [ -d "$profile_dir" ] || continue
        for profile in "''${profile_dir}profile" "''${profile_dir}home-manager"; do
          [ -e "$profile" ] && delete_old_generations "$profile"
        done
      done

      nix-store --gc
    '';
    serviceConfig.Type = "oneshot";
  };

  systemd.timers.nix-gc-safe = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
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

    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.default_qdisc" = "fq";
  };
  boot.kernelModules = [ "tcp_bbr" ];

  security.pam.loginLimits = [
    # Increase soft limit for number of open files, default is way too low (~2048)
    {
      domain = "*"; # Applies to all users
      type = "soft"; # Soft limit
      item = "nofile"; # Number of file descriptors
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
