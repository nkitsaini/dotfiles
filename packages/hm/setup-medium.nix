# Has everything except for desktop manager.
# It is good to be used in nixos or standalone home-manager for desktop setups.

{ config, pkgs, nur, ... }: ({
  # modules = [
  #   nur.hmModules.nur
  # ];
  imports = [
    nur.hmModules.nur
    ./shell
    ./wezterm
    ./tms
    ./helix
    ./firefox.nix
    ./xdg_config.nix
    ./yt-dlp.nix
    ./vcs.nix
    ./yazi.nix
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
      vim.print("Config done")
    '';
  };
  programs.tealdeer = {
    enable = true;
    settings = { updates = { auto_update = true; }; };
  };
  programs.gitui.enable = true;
  programs.gitui.keyConfig =
    builtins.readFile ./gitui_keybindings.ron;

  xsession.enable = true;
  programs.nix-index = { enable = true; };

  services.batsignal = { enable = true; };

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
          location = "budla.lan:5000/";
        }
        {
          insecure = true;
          location = "budla.lan/containers";
        }
        {
          insecure = true;
          location = "budla.lan/docker";
        }
      ];
    };

  home.file.".cargo/config.toml".text = ''
    [registries.crates-io]
    protocol = "sparse"
  '';

  # Home Directories
  home.file."external/.keep".text = ""; # External repos
  home.file."mnt/.keep".text = ""; # mount points
  home.file."tmp/.keep".text = ""; # temporary directory
  home.file."music/.keep".text = ""; # temporary directory
  home.file."video/.keep".text = ""; # temporary directory
  home.file."downloads/.keep".text = ""; # downloads directory

  qt.enable = true;
  qt.platformTheme = "qtct";
  xdg.configFile."qt5ct/qt5ct.conf".text = ''
    [Appearance]
    icon_theme=breeze
  '';

  programs.eza = { enable = true; };

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = with pkgs; [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.

    # Nix specific
    cached-nix-shell

    # httpie in rust
    xh
    difftastic

    # For yazi
    yazi
    unar
    exiftool
    # mpv
    mediainfo

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
    vlc
    github-desktop
    pavucontrol
    qrencode
    qpdf
    gcc
    python312
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
    brave
    bun
    ncdu
    caddy

    # Code specific
    nixfmt
    ruff
    lazygit
    nodejs_20
    (writeScriptBin "copilot" ''
      #!/usr/bin/env bash
      exec ${nodejs_20}/bin/node ${vimPlugins.copilot-vim}/dist/agent.js
    '')

    # I3 specific
    i3
    rofi
    trashy
    pulseaudio
    playerctl
    brightnessctl

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
    libnotify
    obs-studio
    iptables
    bruno
    tree
    podman
    podman-compose
    sqlite
    litecli
    tokei
    valgrind
    wget
    evcxr

    # btrfs
    compsize

    sshfs

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
  home.sessionVariables = { };

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
}

)

