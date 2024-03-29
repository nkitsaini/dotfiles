# This is a nixos package (not home-manager)
{ pkgs, ... }:
let

  left = "h";
  right = "l";
  up = "k";
  down = "j";
  terminal_cmd = "${pkgs.wezterm}/bin/wezterm";

  out_laptop = "eDP-1";
  out_monitor = "HDMI-A-1";

  _touchpad = {
    click_method = "clickfinger";
    tap = "enabled";
    dwt = "enabled"; # disable while typing
    scroll_method = "two_finger";
    natural_scroll = "disabled";
    scroll_factor = "0.75";
    accel_profile = "adaptive";
  };
  _keyboard = {
    xkb_layout = "us";
    repeat_rate = "50";
    repeat_delay = "160";
  };

  username = import ../../../users/kit/username.nix;

  menu =
    "${pkgs.rofi-wayland}/bin/rofi -terminal ${terminal_cmd} -show drun -show-icons";
in {

  # Random configuration required to make sway work
  imports = [ ./sway-knobs.nix ];

  home-manager.users.${username} = {
    home.packages = with pkgs; [
      wl-clipboard
      swaylock
      swayidle
      xwayland
      grim
      slurp
      (pkgs.writeScriptBin "screenshot" ''
        #!${pkgs.bash}/bin/bash

      '')
    ];
    imports = [ ../../hm/waybar ];

    services.copyq = { enable = true; };
    # programs.swaylock.enable = true;
    services.mako = {
      enable = true;
      padding = "15,20";
      # # backgroundColor = "#3b224cF0";
      # backgroundColor = "#281733F0";
      # textColor = "#ebeafa";
      borderSize = 2;
      # borderColor = "#a4a0e8";
      defaultTimeout = 5000;
      markup = true;
      format = "<b>%s</b>\\n\\n%b";

      # TODO:
      # [hidden]
      # format=(and %h more)
      # text-color=#999999

      # [urgency=high]
      # text-color=#F22C86
      # border-color=#F22C86
      # border-size=4
    };

    wayland.windowManager.sway.enable = true;
    wayland.windowManager.sway.systemd.enable = true;
    wayland.windowManager.sway.xwayland = true;
    wayland.windowManager.sway.wrapperFeatures = {
      base = true;
      gtk = true;
    };

    wayland.windowManager.sway.config = rec {
      modifier = "Mod1";
      focus.followMouse = "always";
      terminal = "${terminal_cmd}";
      input = {
        "type:touchpad" = _touchpad;
        "type:keyboard" = _keyboard;
      };

      output = {
        # Can't use negative indexes due to https://github.com/swaywm/sway/wiki#mouse-events-clicking-scrolling-arent-working-on-some-of-my-workspaces
        "${out_laptop}" = { position = "0,1080"; };
        "${out_monitor}" = {
          resolution = "2560x1080";
          position = "0,0";
        };
      };

      inherit left up right down;

      keybindings = {

        # Focus
        "${modifier}+${left}" = "focus left";
        "${modifier}+${down}" = "focus down";
        "${modifier}+${up}" = "focus up";
        "${modifier}+${right}" = "focus right";

        # Move Windows
        "${modifier}+Shift+${left}" = "move left";
        "${modifier}+Shift+${down}" = "move down";
        "${modifier}+Shift+${up}" = "move up";
        "${modifier}+Shift+${right}" = "move right";

        # move focused workspace between monitors (wraps around)
        "${modifier}+Ctrl+${up}" = "move workspace to output up";
        "${modifier}+Ctrl+${left}" = "move workspace to output left";
        "${modifier}+Ctrl+${right}" = "move workspace to output right";
        "${modifier}+Ctrl+${down}" = "move workspace to output down";

        "${modifier}+semicolon" = "split h";
        "${modifier}+Shift+e" = "exec i3-msg exit";

        # TODO: remove nixGL ones moved to NixOS
        "${modifier}+Return" = "exec ${terminal}";
        "${modifier}+d" =
          "exec ${menu}"; # run rofi with nixGL so all program opened inherit it

        "${modifier}+Shift+c" = "reload";
        "${modifier}+Shift+r" = "restart";
        "${modifier}+Shift+q" = "kill";

        # Workspaces
        "${modifier}+1" = "workspace number 1";
        "${modifier}+2" = "workspace number 2";
        "${modifier}+3" = "workspace number 3";
        "${modifier}+4" = "workspace number 4";
        "${modifier}+5" = "workspace number 5";
        "${modifier}+6" = "workspace number 6";
        "${modifier}+7" = "workspace number 7";
        "${modifier}+8" = "workspace number 8";
        "${modifier}+9" = "workspace number 9";

        "${modifier}+Shift+1" = "move container to workspace number 1";
        "${modifier}+Shift+2" = "move container to workspace number 2";
        "${modifier}+Shift+3" = "move container to workspace number 3";
        "${modifier}+Shift+4" = "move container to workspace number 4";
        "${modifier}+Shift+5" = "move container to workspace number 5";
        "${modifier}+Shift+6" = "move container to workspace number 6";
        "${modifier}+Shift+7" = "move container to workspace number 7";
        "${modifier}+Shift+8" = "move container to workspace number 8";
        "${modifier}+Shift+9" = "move container to workspace number 9";

        "${modifier}+Shift+minus" = "move scratchpad";
        "${modifier}+minus" = "scratchpad show";

        # switch layout style
        "${modifier}+s" = "layout stacking";
        "${modifier}+w" = "layout tabbed";
        "${modifier}+e" = "layout toggle split";

        "${modifier}+f" = "fullscreen toggle";
        "${modifier}+a" = "focus parent";

        # Toggle the current focus between tiling and floating mode
        "${modifier}+Shift+space" = "floating toggle";
        "${modifier}+Shift+Ctrl+space" = "sticky toggle";

        # Swap focus between the tiling area and the floating area
        "${modifier}+space" = "focus mode_toggle";

        "${modifier}+r" = "mode resize";

        "XF86MonBrightnessUp" =
          "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5+%";
        "XF86MonBrightnessDown" =
          "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5-%";

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
        border = 2;
      };

      bars = [ ];

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
  };
}
