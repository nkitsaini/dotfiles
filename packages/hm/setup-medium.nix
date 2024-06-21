# Has everything except for desktop manager.
# It is good to be used in nixos or standalone home-manager for desktop setups.

{ config, pkgs, inputs, nixGLCommandPrefix ? "", ... }: ({
  # modules = [
  #   nur.hmModules.nur
  # ];
  imports = [
    inputs.nur.hmModules.nur
    ./shell
    ./wezterm
    ./tms
    ./helix
    ./firefox.nix
    ./xdg_config.nix
    ./yt-dlp.nix
    ./vcs.nix
    ./yazi.nix
    ./syncthing.nix
    ./mpv
    ./k9s
    ./cmus
  ];
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

  gtk = {
    enable = true;
    cursorTheme.name = "Adwaita";
    cursorTheme.package = pkgs.gnome.adwaita-icon-theme;
    theme.name = "adw-gtk3-light";
    theme.package = pkgs.adw-gtk3;
    iconTheme = {
      package = pkgs.gnome.adwaita-icon-theme;
      name = "adwaita-icon-theme";
    };
  };
  programs.gh.enable = true;
  programs.ssh.enable = true;
  programs.feh.enable = true;
  programs.zathura.enable = true;
  # programs.zoxide.enable = true;

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

  programs.alacritty = {
    enable = true;
    settings = {
      import = [ "${pkgs.alacritty-theme}/gruvbox_dark.toml" ];
      env = { XTERM_VERION = "9999"; };
      font = { size = 16; };
      font.normal = {
        family = "Noto Sans Mono";
        style = "Regular";
      };
      scrolling = { history = 10000; };
    };
  };

  programs.neovim = {
    enable = true;
    vimAlias = true;
    plugins = [
      pkgs.vimPlugins.copilot-vim
      pkgs.vimPlugins.vim-fugitive
      pkgs.vimPlugins.neogit
      pkgs.vimPlugins.tokyonight-nvim
      pkgs.vimPlugins.diffview-nvim
      pkgs.vimPlugins.telescope-nvim
      pkgs.vimPlugins.which-key-nvim
      pkgs.vimPlugins.plenary-nvim
      pkgs.vimPlugins.obsidian-nvim
      # pkgs.vimPlugins.vim-markdown
    ];
    extraLuaConfig = ''
      local neogit = require('neogit')
      neogit.setup {}

      vim.g.mapleader = ' '
      vim.opt.termguicolors = true
      vim.cmd 'colorscheme tokyonight-storm'

      local builtin = require('telescope.builtin')
      vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
      vim.keymap.set('n', '<leader>fg', builtin.live_grep, {})
      vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
      vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
      vim.print("Config done")
      vim.opt.number = true


      -- Which Key
      vim.o.timeout = true
      vim.o.timeoutlen = 300
      require("which-key").setup {}
      require("obsidian").setup({
        workspaces = {
          {
            name ="notes",
            path="~/code/notes"
          }
        }
      })

    '';
  };
  programs.tealdeer = {
    enable = true;
    settings = { updates = { auto_update = true; }; };
  };
  programs.gitui.enable = true;
  programs.gitui.keyConfig = builtins.readFile ./gitui_keybindings.ron;

  xsession.enable = true;
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

  # TODO: Move to nix config using registeries v2 after https://github.com/NixOS/nixpkgs/issues/280288
  xdg.configFile."containers/registries.conf".source =
    (pkgs.formats.toml { }).generate "registeries.conf" {
      # unqualified-search-registries = [ "quay.io" "docker.io" ];
      unqualified-search-registries = [ "docker.io" ];
      registry = [
        {
          insecure = true;
          location = "oogway:5000/";
        }
        {
          insecure = true;
          location = "oogway/containers";
        }
        {
          insecure = true;
          location = "oogway/docker";
        }
      ];
    };

  home.file.".cargo/config.toml".text = ''
    [registries.crates-io]
    protocol = "sparse"
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

  qt.enable = true;
  qt.platformTheme.name = "qtct";
  xdg.configFile."qt5ct/qt5ct.conf".text = ''
    [Appearance]
    icon_theme=breeze
  '';

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

      # httpie in rust
      xh

      # hello
      # qbittorrent
      deluge
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
      obsidian
      wl-screenrec
      vlc
      # mpv
      xorg.xset # I see a vlc warning reguarding xset missing. Just in case.
      pavucontrol
      qrencode
      qpdf
      s3fs
      gcc
      python312
      python312Packages.pipx
      kubectl
      kubectl-tree
      kubectx
      sd
      rsync
      nmap
      minio-client
      ffmpeg
      xfce.thunar
      kopia
      xdragon
      ddcutil
      tmux
      zellij
      tmuxp
      just
      grc
      fzf
      cargo-cross
      hyperfine
      alacritty-theme
      wezterm
      bun
      ncdu
      caddy
      archivemount
      ethtool
      sioyek
      gnome.eog
      qimgv
      uv
      file
      # busybox
      lsof
      ntfs3g
      openssl
      iperf

      # inputs.nkitsaini_notes_utils.packages.${system}.default

      # Code specific
      alejandra
      ruff
      lazygit
      nodejs_20
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
          exec nix run ${config.home.homeDirectory}/code/shoal/notes_utils/rs -- "$@"
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

      # I3 specific
      i3
      rofi
      trashy
      pulseaudio
      playerctl
      brightnessctl
      jc # convert common command outputs to json

      # Xorg
      xorg.xev

      # MTP
      jmtpfs

      # From old fish history
      acpi
      aria2
      asciinema
      bandwhich
      bc
      bear
      biome
      bitwarden-cli
      dig
      delve
      dolphin
      duckdb
      fortune
      gdb
      gen-license
      hexyl
      htop
      httpie
      iperf3
      gnumake
      hwatch
      hyperfine
      mold
      tmate
      tailscale
      libnotify
      iptables
      bruno
      tree
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
      compsize

      sshfs
      gparted

      binutils
      coreutils
      curl
      dnsutils
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
    ] ++ (if nixGLCommandPrefix != "" then
      [
        (writeShellApplication {
          name = "nixgl-run";
          text = ''
            exec ${nixGLCommandPrefix} -- "$@"
          '';
        })
      ]
    else
      [ ]);

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

)

