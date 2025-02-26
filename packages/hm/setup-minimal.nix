# non-gui stuff
{ config, pkgs, inputs, nixGLCommandPrefix ? "", ... }: {
  imports = [
    # inputs.nur.homeManager.default
    # inputs.nur.hmModules.nur
    ./shell
    ./tms
    ./helix
    ./xdg_config.nix
    ./yt-dlp.nix
    ./vcs.nix
    ./yazi.nix
    ./syncthing.nix
    ./k9s
    ./cmus
    ./aria2
    ./neovim
    ./taskwarrior
    # ../../modules/hm
  ];

  # kit.neovim.enable = true;
  # username and home directory are provided by the parent home.nix

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  nixpkgs.config.allowUnfree = true;
  systemd.user.enable = true;
  systemd.user.startServices = true;

  programs.gh.enable = true;

  programs.ssh.enable = true;
  services.ssh-agent.enable = true;

  programs.feh.enable = true;
  programs.zathura.enable = true;

  # Stores configs I don't want to be in Nix
  programs.ssh.extraConfig =
    "Include ${config.home.homeDirectory}/.ssh/user_config";

  programs.ripgrep = {
    enable = true;
    arguments = [ "-S" ];
  };

  programs.bottom = {
    enable = true;
    settings = { flags = { color = "gruvbox-light"; }; };
  };

  programs.bat = {
    enable = true;
    config = {
      pager = "delta";
      theme = "gruvbox-light";
    };
  };

  programs.tealdeer = {
    enable = true;
    settings = { updates = { auto_update = true; }; };
  };
  programs.gitui.enable = true;
  programs.gitui.keyConfig = builtins.readFile ./gitui_keybindings.ron;

  programs.nix-index = { enable = true; };

  services.batsignal = { enable = true; };
  services.network-manager-applet.enable = true;

  xdg.configFile."nixpkgs/config.nix".text = ''
     {
      packageOverrides = pkgs: {
        nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
          inherit pkgs;
        };
      };
    }
  '';

  home.file.".cargo/config.toml".text = ''
    [registries.crates-io]
    protocol = "sparse"
    [target.x86_64-unknown-linux-gnu]
    linker = "${pkgs.clang}/bin/clang"
    rustflags = ["-C", "link-arg=--ld-path=${pkgs.mold}/bin/mold"]
  '';

  # Home Directories
  home.file."external/.keep".text = ""; # External repos
  home.file."code/.keep".text = ""; # Personal repos
  home.file."workspace/.keep".text = ""; # Work repos
  home.file."mnt/.keep".text = ""; # mount points
  home.file."tmp/.keep".text = ""; # temporary directory
  home.file."Music/.keep".text = ""; # temporary directory
  home.file."videos/.keep".text = ""; # temporary directory
  home.file."Downloads/.keep".text = ""; # downloads directory
  home.file."pictures/.keep".text = ""; # downloads directory

  programs.eza = { enable = true; };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs;
    [
      # # Adds the 'hello' command to your environment. It prints a friendly
      # # "Hello, world!" when run.

      # Nix specific
      cached-nix-shell
      difftastic

      # For yazi
      yazi
      unar
      exiftool
      # mpv
      mediainfo


      cmake

      # httpie in rust
      xh

      # hello
      # qbittorrent
      xclip
      jq
      fd
      killall
      jless
      hexyl
      zip
      unzip
      gnutar
      rustup

      qrencode
      s3fs
      gcc
      python312
      python312Packages.ipython
      python312Packages.pipx
      python312Packages.tkinter # for turtle
      kubectl
      kubectl-tree
      kubectx
      sd
      rsync
      nmap
      minio-client
      ffmpeg
      kopia
      rclone
      ddcutil
      tmux
      tmuxp
      just
      grc
      fzf
      cargo-cross
      hyperfine
      bun
      ncdu
      dua # ncdu alternative
      caddy
      archivemount
      ethtool
      uv
      file
      lsof
      ntfs3g
      openssl
      iperf


      # Utils
      pv
      pdftk
      hwinfo
      beep
      ascii

      # Code specific
      nixfmt-rfc-style
      ruff
      lazygit
      nodejs_20
      (writeScriptBin "notes" ''
        #!${pkgs.dash}/bin/dash
        cd ${config.home.homeDirectory}/code/notes

        # HACK: without `:e` otherwise norg doesn't load on default file
        exec nvim -c ':e'
      '')

      (writeScriptBin "copilot" ''
        #!${pkgs.dash}/bin/dash
        exec ${nodejs_20}/bin/node ${vimPlugins.copilot-vim}/dist/agent.js
      '')

      (writeScriptBin "audiobook_generator" ''
        #!${pkgs.dash}/bin/dash
        exec nix run ${config.home.homeDirectory}/code/shoal/audiobook_generator --  "$@"
      '')
      (writeScriptBin "hh" ''
        #!${pkgs.dash}/bin/dash
        exec nix run ${config.home.homeDirectory}/code/shoal/helios_helper -- "$@"
      '')
      (writeShellApplication {
        name = "bw-util";
        text = ''
          exec nix run ${config.home.homeDirectory}/code/shoal/bitwarden_util -- "$@"
        '';
      })
      (writeShellApplication {
        name = "notes-util";
        text = ''
          exec nix run ${config.home.homeDirectory}/code/shoal/notes_utils -- "$@"
        '';
      })
      (writeShellApplication {
        name = "audio_cleaner";
        text = ''
          exec nix run ${config.home.homeDirectory}/code/shoal/audio_cleaner -- "$@"
        '';
      })
      (writeShellApplication {
        name = "mit_ocw_utils";
        text = ''
          exec nix run ${config.home.homeDirectory}/code/shoal/mit_ocw_utils -- "$@"
        '';
      })
      (writeShellApplication {
        name = "make_public";
        text = ''
          exec nix run ${config.home.homeDirectory}/code/shoal/make_public -- "$@"
        '';
      })
      (writeShellApplication {
        name = "cuckoo_controller";
        text = ''
          exec nix run ${config.home.homeDirectory}/code/shoal/cuckoo_controller -- "$@"
        '';
      })

      # I3 specific
      trashy
      jc # convert common command outputs to json

      # MTP
      jmtpfs

      # From old fish history
      acpi
      rqbit
      asciinema
      bandwhich
      bc
      bear
      biome
      bitwarden-cli
      dig
      delve
      duckdb
      fortune
      gdb
      gen-license
      hexyl
      htop
      httpie
      iperf3
      gnumake
      pkg-config
      hwatch
      hyperfine
      mold
      tmate
      tailscale
      libnotify
      iptables
      bruno
      tree
      broot
      podman
      podman-compose
      sqlite
      litecli
      pgcli
      tokei
      valgrind
      wget
      duf # better df

      # btrfs

      # Broken: https://github.com/NixOS/nixpkgs/issues/336006
      # compsize

      sshfs

      binutils
      coreutils
      curl
      dnsutils
      usbutils # lsusb
      lshw
      dosfstools
      powertop
      iputils
      # moreutils
      nmap
      util-linux
      whois
      # Kernel modules
      # TODO: enable when on NixOS
      # linuxKernel.packages.linux_6_7.ddcci-driver

      # # It is sometimes useful to fine-tune packages, for example, by applying
      # # overrides. You can do that directly here, just don't forget the
      # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
      # # fonts?
      # (nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

      # # You can also create simple shell scripts directly inside your
      # # configuration. For example, this adds a command 'my-hello' to your
      # # environment:
      # (writeShellScriptBin "my-hello" ''
      #   echo "Hello, ${config.home.username}!"
      # '')
    ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };

  # Home Manager can also manage your environment variables through
  # 'home.sessionVariables'. If you don't want to manage your shell through Home
  # Manager then you have to manually source 'hm-session-vars.sh' located at
  # either
  #
  #  ~/.nix-profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  ~/.local/state/nix/profiles/profile/etc/profile.d/hm-session-vars.sh
  #
  # or
  #
  #  /etc/profiles/per-user/ankit/etc/profile.d/hm-session-vars.sh
  #
  home.sessionVariables = {
    LC_ALL = "en_US.UTF-8";
    LANG = "en_US.UTF-8";
    NIXPKGS_ALLOW_UNFREE = "1";
  };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}
