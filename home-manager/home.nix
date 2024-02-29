{ config, pkgs, lib, ... }:
(let
  username = "ankit";
  homeDirectory = "/home/${username}";
  childModuleArgs = { inherit pkgs lib config homeDirectory; };


  # recurisvely merges all the sets in the list
  _nRecursiveUpdate = lib.lists.foldr (a: b: lib.attrsets.recursiveUpdate a b) { };
in   {
    imports = [ ./i3.nix ./shell.nix ];

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

    programs.bottom.enable = true;
    programs.alacritty = {
      enable = true;
      settings = {
        import = [ "${pkgs.alacritty-theme}/solarized_light.toml" ];
      };
    };

    xsession.enable = true;

    # The home.packages option allows you to install Nix packages into your
    # environment.
    home.packages = [
      # # Adds the 'hello' command to your environment. It prints a friendly
      # # "Hello, world!" when run.
      # pkgs.hello
      pkgs.tmux
      pkgs.tmuxp
      pkgs.nil
      pkgs.just
      pkgs.grc
      pkgs.fzf
      pkgs.cargo-binstall
      pkgs.cargo-cross
      pkgs.hyperfine
      pkgs.tmux-sessionizer
      pkgs.alacritty-theme
      pkgs.brave
      pkgs.i3
      pkgs.nixfmt
      pkgs.rofi
      pkgs.firefox

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
    home.sessionVariables = { EDITOR = "hx"; };

    # Let Home Manager install and manage itself.
    programs.home-manager.enable = true;
  }

)

