{ config, pkgs, lib, enableNixGL, ... }:
let
  left = "h";
  right = "l";
  up = "k";
  down = "j";
  terminal_cmd = "${pkgs.wezterm}/bin/wezterm";

  bg-color = "#1f242f";
  inactive-bg-color = "#1f242f";
  text-color = "#f3f4f5";
  inactive-text-color = "#676E7D";
  urgent-bg-color = "#E53935";
  nixGLCommandPrefix = if enableNixGL then "nixGL " else "";
  menu =
    "${pkgs.rofi}/bin/rofi -terminal ${terminal_cmd} -show drun -show-icons";
in {
  xsession.windowManager.i3.enable = true;

  xsession.initExtra = ''
    xset r rate 160 50
  '';

  xsession.windowManager.i3.config = rec {
    terminal = "${nixGLCommandPrefix}${terminal_cmd}";

    keybindings = let mod = config.xsession.windowManager.i3.config.modifier;
    in {

      # Focus
      "${mod}+${left}" = "focus left";
      "${mod}+${down}" = "focus down";
      "${mod}+${up}" = "focus up";
      "${mod}+${right}" = "focus right";

      # Move Windows
      "${mod}+Shift+${left}" = "move left";
      "${mod}+Shift+${down}" = "move down";
      "${mod}+Shift+${up}" = "move up";
      "${mod}+Shift+${right}" = "move right";

      # move focused workspace between monitors (wraps around)
      "${mod}+Ctrl+${up}" = "move workspace to output up";
      "${mod}+Ctrl+${left}" = "move workspace to output left";
      "${mod}+Ctrl+${right}" = "move workspace to output right";
      "${mod}+Ctrl+${down}" = "move workspace to output down";

      "${mod}+semicolon" = "split h";
      "${mod}+Shift+e" = "exec i3-msg exit";

      # TODO: remove nixGL ones moved to NixOS
      "${mod}+Return" = "exec ${terminal}";
      "${mod}+d" =
        "exec ${nixGLCommandPrefix}${menu}"; # run rofi with nixGL so all program opened inherit it

      "${mod}+Shift+c" = "reload";
      "${mod}+Shift+r" = "restart";
      "${mod}+Shift+q" = "kill";

      # Workspaces
      "${mod}+1" = "workspace number 1";
      "${mod}+2" = "workspace number 2";
      "${mod}+3" = "workspace number 3";
      "${mod}+4" = "workspace number 4";
      "${mod}+5" = "workspace number 5";
      "${mod}+6" = "workspace number 6";
      "${mod}+7" = "workspace number 7";
      "${mod}+8" = "workspace number 8";
      "${mod}+9" = "workspace number 9";

      "${mod}+Shift+1" = "move container to workspace number 1";
      "${mod}+Shift+2" = "move container to workspace number 2";
      "${mod}+Shift+3" = "move container to workspace number 3";
      "${mod}+Shift+4" = "move container to workspace number 4";
      "${mod}+Shift+5" = "move container to workspace number 5";
      "${mod}+Shift+6" = "move container to workspace number 6";
      "${mod}+Shift+7" = "move container to workspace number 7";
      "${mod}+Shift+8" = "move container to workspace number 8";
      "${mod}+Shift+9" = "move container to workspace number 9";

      # switch layout style
      "${mod}+s" = "layout stacking";
      "${mod}+w" = "layout tabbed";
      "${mod}+e" = "layout toggle split";

      "${mod}+f" = "fullscreen toggle";
      "${mod}+a" = "focus parent";

      # Toggle the current focus between tiling and floating mode
      "${mod}+Shift+space" = "floating toggle";
      "${mod}+Shift+Ctrl+space" = "sticky toggle";

      # Swap focus between the tiling area and the floating area
      "${mod}+space" = "focus mode_toggle";

      "${mod}+r" = "mode resize";

      "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5+%";
      "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5-%";

      ## Pulse Audio controls
      "XF86AudioRaiseVolume" =
        "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ +5%"; # increase sound volume
      "XF86AudioLowerVolume" =
        "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-volume @DEFAULT_SINK@ -5%"; # decrease sound volume
      "XF86AudioMute" =
        "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle"; # mute sound
      "XF86AudioMicMute" =
        "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle"; # mute mic audio

      "XF86AudioPlay" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
      "XF86AudioPause" = "exec ${pkgs.playerctl}/bin/playerctl play-pause";
      "XF86AudioNext" = "exec ${pkgs.playerctl}/bin/playerctl next";
      "XF86AudioPrev" = "exec ${pkgs.playerctl}/bin/playerctl previous";
    };

    window = {
      titlebar = false;
      border = 3;
    };

    bars = [{
      id = "bar-0";
      position = "bottom";
      hiddenState = "hide";
      # These are the only two commands that differ
      # statusCommand = "${pkgs.i3blocks}/bin/i3blocks";
      statusCommand = "${pkgs.i3status}/bin/i3status";
      command = "${pkgs.i3}/bin/i3bar";
      fonts = {
        names = [ "Noto Sans" ];
        size = 10.0;
      };

      colors = {
        # The colors for the workspace button for an active workspace.
        activeWorkspace = {
          background = bg-color;
          border = inactive-text-color;
          text = inactive-text-color;
        };

        # The background color of the bar.
        background = bg-color;

        # The colors for binding mode indicators.
        bindingMode = {
          background = bg-color;
          border = urgent-bg-color;
          text = text-color;
        };

        # The colors for focused workspaces.
        focusedWorkspace = {
          background = bg-color;
          border = bg-color;
          text = text-color;
        };

        # The colors for inactive workspaces.
        inactiveWorkspace = {
          background = inactive-bg-color;
          border = inactive-bg-color;
          text = inactive-text-color;
        };

        # The color for status line separators.
        separator = "#757575";

        # The foreground color for text for the statusline.
        # statusline = colorNames.base00;

        # The colors to use for urgent workspaces.
        urgentWorkspace = {
          background = urgent-bg-color;
          border = urgent-bg-color;
          text = text-color;
        };
      };
    }];

    modes = {
      resize = {
        "${left}" = "resize shrink width 10 px";
        "${down}" = "resize grow height 10 px";
        "${up}" = "resize shrink height 10 px";
        "${right}" = "resize grow width 10 px";
        "Left" = "resize shrink width 10 px";
        "Down" = "resize grow height 10 px";
        "Up" = "resize shrink height 10 px";
        "Right" = "resize grow width 10 px";
        "Escape" = "mode default";
        "Return" = "mode default";
      };
    };
  };

  programs.i3status.enable = true;
  services.polybar = {
    enable = false;
    script = "polybar &";
    extraConfig = ''
    wm-restack = i3
    ${builtins.readFile "${pkgs.polybar}/etc/polybar/config.ini"}
    '';
    # settings = {
    #   "bar/bottom" = {
    #     height = "3%";
    #     width = "100%";
    #     modules-right = "volume";
    #   };
    #   "module/volume" = {
    #     type = "internal/pulseaudio";
    #     format.volume = "<ramp-volume> <label-volume>";
    #     label.muted.text = "🔇";
    #     label.muted.foreground = "#666";
    #     ramp.volume = [ "🔈" "🔉" "🔊" ];
    #     click.right = "pavucontrol &";
    #   };
    # };
  };
  programs.i3blocks = {
    enable = false;
    bars = {
      config = {
        time = {
          command = "date +%r";
          interval = 1;
        };
        # Make sure this block comes after the time block
        date = lib.hm.dag.entryAfter [ "time" ] {
          command = "date +%d";
          interval = 5;
        };
        # And this block after the example block
        example = lib.hm.dag.entryAfter [ "date" ] {
          command = "echo hi $(date +%s)";
          interval = 3;
        };
      };
    };
  };

}
