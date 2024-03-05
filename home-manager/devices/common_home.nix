{ config, pkgs, nur, ... }: ({
  # modules = [
  #   nur.hmModules.nur
  # ];
  imports = [
    nur.hmModules.nur
    ../packages/i3.nix
    ../packages/shell
    ../packages/wezterm
    ../packages/tms
    ../packages/helix
    ../packages/firefox.nix
    ../packages/xdg_config.nix
    ../packages/yt-dlp.nix
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

  programs.gh.enable = true;
  programs.ssh.enable = true;
  programs.feh.enable = true;
  programs.zathura.enable = true;

  # Stores configs I don't want to be in Nix
  programs.ssh.extraConfig =
    "Include ${config.home.homeDirectory}/.ssh/user_config";

  programs.git = {
    # username and email are defined
    # by device specific config
    enable = true;

    delta = {
      enable = true;
      options = {
        navigate = true;
        syntax-theme = "Monokai Extended Light";
        features = "side-by-side line-numbers decorations"; # hyperlinks
        whitespace-error-style = "22 reverse";
        decorations = {
          commit-decoration-style = "bold yellow box ul";
          file-style = "bold yellow ul";
          file-decoration-style = "none";
        };
      };
    };
    extraConfig = {
      diff = {
        algorithm = "histogram";
        renames = "copies";
        mnemonicprefix = true;
        colormoved = "default";
      };
      url = { "git@github.com:" = { insteadOf = "gh:"; }; };
      url = { "git@github.com:nkitsaini/" = { insteadOf = "ghme:"; }; };
      init.defaultBranch = "main";
      help.autocorrect = 1;

      push = {
        default = "simple";
        autoSetupRemote = true;
      };
      merge = { conflictstyle = "zdiff3"; };
      rerere = { enabled = 1; };
      pull = { rebase = true; };
      rebase = { autostash = true; };
    };
    aliases = {
      l =
        "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset %C(yellow)%an%Creset' --all --abbrev-commit --date=relative";
      ls = "log --stat --oneline";
      pf = "push --force-with-lease";
      p = "push";
    };
  };

  programs.ripgrep = {
    enable = true;
    arguments = [ "-S" ];
  };

  programs.bottom = {
    enable = true;
    settings = { flags = { color = "gruvbox-light"; }; };
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
    plugins = [ pkgs.vimPlugins.copilot-vim pkgs.vimPlugins.vim-fugitive ];
  };
  programs.tealdeer = {
    enable = true;
    settings = {
      updates = {
        auto_update = true;
      };
    };
  };
  programs.gitui.enable = true;
  programs.gitui.keyConfig = builtins.readFile ../packages/gitui_keybindings.ron;

  xsession.enable = true;
  programs.nix-index = { enable = true; };

  services.batsignal = {
    enable = true;
  };

  xdg.configFile."nixpkgs/config.nix".text = ''
     {
      packageOverrides = pkgs: {
        nur = import (builtins.fetchTarball "https://github.com/nix-community/NUR/archive/master.tar.gz") {
          inherit pkgs;
        };
      };
    }
  '';

  xdg.enable = true;
  /* [Default Applications]
     x-scheme-handler/http=firefox.desktop
     x-scheme-handler/https=firefox.desktop
     x-scheme-handler/chrome=firefox.desktop
     text/html=firefox.desktop
     application/x-extension-htm=firefox.desktop
     application/x-extension-html=firefox.desktop
     application/x-extension-shtml=firefox.desktop
     application/xhtml+xml=firefox.desktop
     application/x-extension-xhtml=firefox.desktop
     application/x-extension-xht=firefox.desktop

     [Added Associations]
     x-scheme-handler/http=firefox.desktop;
     x-scheme-handler/https=firefox.desktop;
     x-scheme-handler/chrome=firefox.desktop;
     text/html=firefox.desktop;
     application/x-extension-htm=firefox.desktop;
     application/x-extension-html=firefox.desktop;
     application/x-extension-shtml=firefox.desktop;
     application/xhtml+xml=firefox.desktop;
     application/x-extension-xhtml=firefox.desktop;
     application/x-extension-xht=firefox.desktop;
     [
     "x-scheme-handler/http"
     "x-scheme-handler/https"
     "x-scheme-handler/chrome"
     "text/html"
     "application/x-extension-htm"
     "application/x-extension-html"
     "application/x-extension-shtml"
     "application/xhtml+xml"
     "application/x-extension-xhtml"
     "application/x-extension-xht" ]
  */

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

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.

    # Nix specific
    pkgs.cached-nix-shell

    # For yazi
    pkgs.yazi
    pkgs.unar
    pkgs.exiftool
    # pkgs.mpv
    pkgs.mediainfo

    # pkgs.hello
    # pkgs.qbittorrent
    pkgs.deluge
    pkgs.xclip
    pkgs.jq
    pkgs.fd
    pkgs.jless
    pkgs.zip
    pkgs.unzip
    pkgs.gnutar
    pkgs.zsh
    pkgs.obsidian
    pkgs.vlc
    pkgs.github-desktop
    pkgs.mosh
    pkgs.python3
    pkgs.kubectl
    pkgs.sd
    pkgs.rsync
    pkgs.nmap
    pkgs.ffmpeg
    pkgs.xfce.thunar
    pkgs.kopia
    pkgs.xdragon
    pkgs.ddcutil
    pkgs.tmux
    pkgs.zellij
    pkgs.tmuxp
    pkgs.just
    pkgs.grc
    pkgs.fzf
    pkgs.cargo-cross
    pkgs.hyperfine
    pkgs.alacritty-theme
    pkgs.wezterm
    pkgs.brave
    pkgs.bun
    pkgs.ncdu
    pkgs.caddy

    # Code specific
    pkgs.nixfmt
    pkgs.ruff
    pkgs.lazygit
    pkgs.nodejs_20
    (pkgs.writeScriptBin "copilot" ''
      #!/usr/bin/env bash
      exec ${pkgs.nodejs_20}/bin/node ${pkgs.vimPlugins.copilot-vim}/dist/agent.js
    '')

    # I3 specific
    pkgs.i3
    pkgs.rofi
    pkgs.pulseaudio
    pkgs.playerctl
    pkgs.brightnessctl

    # Xorg
    pkgs.xorg.xev

    # MTP
    pkgs.jmtpfs

    # Kernel modules
    # TODO: enable when on NixOS
    # pkgs.linuxKernel.packages.linux_6_7.ddcci-driver

    # # It is sometimes useful to fine-tune packages, for example, by applying
    # # overrides. You can do that directly here, just don't forget the
    # # parentheses. Maybe you want to install Nerd Fonts with a limited number of
    # # fonts?
    # (pkgs.nerdfonts.override { fonts = [ "FantasqueSansMono" ]; })

    # # You can also create simple shell scripts directly inside your
    # # configuration. For example, this adds a command 'my-hello' to your
    # # environment:
    # (pkgs.writeShellScriptBin "my-hello" ''
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
