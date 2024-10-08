{ config, pkgs, lib, ... }: {
  programs.bash = {
    enable = true;
    # bashrcExtra = ''
    #   . ~/oldbashrc
    # '';
    initExtra = ''
      if [ -e "$HOME/.bash_env" ]; then
        . "$HOME/.bash_env"
      fi

      export PATH="${config.home.homeDirectory}/.local/bin:$PATH"
      export PATH="${config.home.homeDirectory}/bin/:$PATH"

      if [[ $(${pkgs.procps}/bin/ps --no-header --pid=$PPID --format=comm) != "fish" && -z ''${BASH_EXECUTION_STRING} ]]
      then
        shopt -q login_shell && LOGIN_OPTION='--login' || LOGIN_OPTION=""
        exec ${pkgs.fish}/bin/fish $LOGIN_OPTION
      fi
    '';
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config = { global = { hide_env_diff = true; }; };
  };

  programs.atuin = {
    enable = true;
    enableBashIntegration = true;
    enableFishIntegration = true;
    flags = [ "--disable-up-arrow" ];
    settings = {
      # Maybe later.
      auto_sync = false;
      enter_accept = true;
      inline_height = 20;
    };
  };

  programs.starship = {
    enable = true;
    enableFishIntegration = true;
    settings = {

      format = lib.concatStrings [
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_state"
        "$git_status"
        "$status"
        "$nix_shell"
        "$cmd_duration"
        "$line_break"
        "$python"
        "$character"
      ];

      git_branch = {
        format = "[$branch]($style)";
        style = "bright-black";
      };

      git_status = {
        format =
          "[[(*$conflicted$untracked$modified$staged$renamed$deleted)](218) ($ahead_behind$stashed)]($style)";
        style = "cyan";
        conflicted = "​";
        untracked = "​";
        modified = "​";
        staged = "​";
        renamed = "​";
        deleted = "​";
        stashed = "≡";
      };

      git_state = {
        format = "([$state( $progress_current/$progress_total)]($style)) ";
        style = "bright-black";
      };

      cmd_duration = {
        format = "[$duration]($style) ";
        style = "yellow";
      };

      python = {
        format = "[$virtualenv]($style) ";
        style = "bright-black";
      };

      status = {
        disabled = false;
        format = " [E-$status]($style) ";
      };

    };
  };

  programs.fish = {
    enable = true;
    plugins = [
      {
        name = "grc";
        src = pkgs.fishPlugins.grc.src;
      }
      {
        name = "fzf";
        src = pkgs.fishPlugins.fzf-fish.src;
      }
      {
        name = "done";
        src = pkgs.fishPlugins.done.src;
      }
    ];
    shellAliases = {
      gs = "git status";
      gc = "git checkout";
      g = "git";

      ## Monitor switch alias
      # Source: https://github.com/rockowitz/ddcutil/wiki/Switching-input-source-on-LG-monitors
      monitor-work =
        "ddcutil -d 1 setvcp xF4 x0090 --i2c-source-addr=x50 --noverify";
      monitor-personal =
        "ddcutil -d 1 setvcp xF4 x0091 --i2c-source-addr=x50 --noverify";
      monitor-brightness = "ddcutil -d 1 setvcp x10";

      j = "z"; # jump
      ll = "${pkgs.eza}/bin/eza -lahgF";
      l = "${pkgs.eza}/bin/eza -F";

      tp = "${pkgs.trashy}/bin/trash put";
      rm = "echo 'use `tp` or `rmforce`'";
      mv = "mv -i";
      rmforce = "${pkgs.coreutils-full}/bin/rm";

      pocker = "docker --context prod";
    };
    shellInit = ''
      # Emulates vim's cursor shape behavior
      # Set the normal and visual mode cursors to a block
      set fish_cursor_default block
      # Set the insert mode cursor to a line
      set fish_cursor_insert line
      # Set the replace mode cursor to an underscore
      set fish_cursor_replace_one underscore
      # The following variable can be used to configure cursor shape in
      # visual mode, but due to fish_cursor_default, is redundant here
      set fish_cursor_visual block

      # Start vim mode
      set -g fish_key_bindings fish_vi_key_bindings


      # Could've sworn this was already the default
      fzf_configure_bindings  --directory=\ct

      # disable ls coloring by grc
      set -U grc_plugin_ignore_execs ls
    '';
  };

  home.packages = [
    (pkgs.writeScriptBin "tmux-times" ''
      #!/usr/bin/env bash
      for pid in $(tmux list-panes -a -F '#{pane_pid}'); do
        for child in $(pgrep -P $pid); do
          ps -p $child -ho etime,comm,args;
        done;
      done
    '')
  ];
  programs.tmux = {
    enable = true;
    # sensible defaults
    sensibleOnTop = true;

    # set by tmux-sensible but the config resets it
    escapeTime = 0;
    historyLimit = 10000;
    aggressiveResize = true;
    # terminal = "tmux-256color";
    # focus-events

    baseIndex = 1;
    clock24 = true;
    keyMode = "vi";

    extraConfig = ''
      ${builtins.readFile ./tmux.conf}
    '';
  };
}
