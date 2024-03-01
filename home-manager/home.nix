{ config, pkgs, lib, nkitsaini_helix, system, ... }:
(let
  username = "ankit";
  homeDirectory = "/home/${username}";
  childModuleArgs = { inherit pkgs lib config homeDirectory; };

  # recurisvely merges all the sets in the list
  _nRecursiveUpdate =
    lib.lists.foldr (a: b: lib.attrsets.recursiveUpdate a b) { };
in {
  imports = [ ./i3.nix ./shell ./wezterm ./tms ./helix ];

  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = username;
  home.homeDirectory = homeDirectory;

  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "23.11"; # Please read the comment before changing.

  programs.gh.enable = true;

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
      import = [ "${pkgs.alacritty-theme}/solarized_light.toml" ];
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
    plugins = [ pkgs.vimPlugins.copilot-vim ];
  };

  xsession.enable = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    # # Adds the 'hello' command to your environment. It prints a friendly
    # # "Hello, world!" when run.
    # pkgs.hello
    pkgs.tmux
    pkgs.zellij
    pkgs.tmuxp
    pkgs.just
    pkgs.grc
    pkgs.fzf
    pkgs.cargo-binstall
    pkgs.cargo-cross
    pkgs.hyperfine
    pkgs.alacritty-theme
    pkgs.wezterm
    pkgs.brave
    pkgs.firefox
    pkgs.bun
    pkgs.ncdu
    pkgs.caddy

    # Code specific
    pkgs.nixfmt
    pkgs.ruff
    pkgs.lazygit
    pkgs.nodejs_20
    (pkgs.writeScriptBin "copilot" ''
      #!/bin/bash
      exec ${pkgs.nodejs_20}/bin/node ${pkgs.vimPlugins.copilot-vim}/dist/agent.js
    '')

    # I3 specific
    pkgs.i3
    pkgs.rofi
    pkgs.light
    pkgs.pulseaudio
    pkgs.playerctl

    # Xorg
    pkgs.xorg.xev

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

