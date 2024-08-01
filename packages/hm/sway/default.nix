# This is a nixos package (not home-manager)
{
  pkgs,
  config,
  system,
  inputs,
  nixGLCommandPrefix ? "",
  disableSwayLock ? false,
  ...
}:
let
  left = "h";
  right = "l";
  up = "k";
  down = "j";
  terminal_cmd = "${pkgs.wezterm}/bin/wezterm";

  sway_display_control = pkgs.writeShellApplication {
    name = "sway-display-control";
    runtimeInputs = with pkgs; [
      sway
      jq
      findutils
    ];
    text = ''
      # usage: sway-display-control off
      # usage: sway-display-control on
      # usage: sway-display-control toggle
      swaymsg -t get_outputs | jq '.[].name' | xargs -I _ swaymsg "output _ dpms $1"
    '';
  };

  turn_off_output_cmd = "${sway_display_control}/bin/sway-display-control off";
  turn_on_output_cmd = "${sway_display_control}/bin/sway-display-control on";
  # Can't get PAM to work on non-nixos (ubuntu) with swaylock
  # It seems like the solution but didn't bother: https://github.com/NixOS/nixpkgs/issues/158025#issuecomment-1616807870
  swaylock_cmd =
    if disableSwayLock then
      turn_off_output_cmd
    else
      "${pkgs.swaylock}/bin/swaylock -i ${(import ../../shared/wallpapers.nix).wallpaper2} --color '#100B1B' -fF";
  out_laptop = "eDP-1";
  out_monitor = "HDMI-A-1";

  _touchpad = {
    click_method = "clickfinger";
    tap = "enabled";
    dwt = "enabled"; # disable while typing
    scroll_method = "two_finger";
    natural_scroll = "enabled";
    scroll_factor = "0.75";
    accel_profile = "adaptive";
  };

  _keyboard = {
    xkb_layout = "us";

    # This only takes effect if inside non-nixos environment.
    # Otherwise interception-tools handles it at `packages/os/keyboard.nix`
    xkb_options = "ctrl:nocaps";
    # xkb_variant = "colemak_dh";
    repeat_rate = "50";
    repeat_delay = "160";
  };

  menu = "${nixGLCommandPrefix}${pkgs.rofi-wayland}/bin/rofi -terminal ${terminal_cmd} -show drun -show-icons";

  wallpaper = (import ../../shared/wallpapers.nix).wallpaper1;
in
{

  home.packages = with pkgs; [
    wl-clipboard
    swaylock
    swayidle
    sway_display_control
    xwayland
    grim
    slurp
  ];
  imports = [
    ../../hm/waybar
    ../wlsunset
  ];
  home.file = {
    ".home-manager-extras/README.md".text = ''
      Generated files to use to configure home-manager without nixos environment.
      - home-manager-wayland.desktop - copy (not symlink) to /usr/share/wayland-sessions/home-manager-wayland.desktop (to enable using sway with gdm/ligthdm etc.)
    '';
    ".home-manager-extras/wayland-session.sh".text = ''
      if [ -e "$HOME/.profile" ]; then
        . "$HOME/.profile"
      fi

      exec ${nixGLCommandPrefix}sway
    '';
    ".home-manager-extras/home-manager-wayland.desktop".text = ''
      [Desktop Entry]
      Name=home manager (as wayland)
      Comment=home manager configured xsession as wayland
      Exec=bash ${config.home.homeDirectory}/.home-manager-extras/wayland-session.sh
      Type=Application
      Keywords=tiling;wm;windowmanager;window;manager;
    '';
  };

  services.copyq = {
    enable = true;
  };
  services.swayidle = {
    enable = true;
    events = [
      {
        event = "before-sleep";
        command = "${pkgs.playerctl}/bin/playerctl pause";
      }
      {
        event = "before-sleep";
        command = swaylock_cmd;
      }
      {
        event = "lock";
        command = swaylock_cmd;
      }
      {
        event = "after-resume";
        command = turn_on_output_cmd;
      }
      {
        event = "unlock";
        command = turn_on_output_cmd;
      }
    ];
    timeouts = [
      {
        timeout = 1200; # Use idlelock on waybar while watching long videos etc.
        command = swaylock_cmd;
      }
      {
        timeout = 3600;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };
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
    # urgency
    extraConfig = ''
      [urgency=high]
      text-color=#CFFFF6
      border-color=#000000
      background-color=#FF0F0F
      border-size=4
    '';
  };

  wayland.windowManager.sway.enable = true;
  # wayland.windowManager.sway.checkConfig = false; # https://discourse.nixos.org/t/services-xserver-xkb-extralayouts-doesnt-seem-to-be-compatible-with-sway/46128
  wayland.windowManager.sway.systemd.enable = true;
  wayland.windowManager.sway.xwayland = true;
  wayland.windowManager.sway.extraSessionCommands = ''
    # For some reason, this script is also run while `nixos-rebuild`, when the ~/.xsession is not available (different fs). So conditional execution.
    # $HOME at that time is /homeless-shelter, which builder uses
    if [ "$HOME" == "${config.home.homeDirectory}" ]; then
      source ${config.home.homeDirectory}/.xsession
    fi
  '';
  wayland.windowManager.sway.wrapperFeatures = {
    base = true;
    gtk = true;
  };

  wayland.windowManager.sway.config = rec {
    modifier = "Mod4";
    focus.followMouse = "always";
    terminal = "${terminal_cmd}";
    input = {
      "type:touchpad" = _touchpad;
      "type:keyboard" = _keyboard;
    };

    output = {
      # Can't use negative indexes due to https://github.com/swaywm/sway/wiki#mouse-events-clicking-scrolling-arent-working-on-some-of-my-workspaces
      "${out_laptop}" = {
        position = "0,1080";
      };
      "${out_monitor}" = {
        resolution = "2560x1080";
        position = "0,0";
      };
    };

    inherit
      left
      up
      right
      down
      ;

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

      "${modifier}+Return" = "exec ${terminal}";
      "${modifier}+d" = "exec ${menu}"; # run rofi with nixGL so all program opened inherit it

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
      # "${modifier}+Shift+Ctrl+space" = "sticky toggle";

      # Swap focus between the tiling area and the floating area
      "${modifier}+space" = "focus mode_toggle";

      "${modifier}+r" = "mode resize";
      "${modifier}+o" = "exec ${turn_on_output_cmd}";
      "${modifier}+Shift+O" = "exec ${turn_off_output_cmd}";
      # "${modifier}+." = "exec ${pkgs.bemoji}/bin/bemoji";

      # Brightness
      "XF86MonBrightnessUp" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5+%";
      "XF86MonBrightnessDown" = "exec ${pkgs.brightnessctl}/bin/brightnessctl set 5-%";

      # Screenshot
      # "Print" = "exec ${pkgs.grim}/bin/grim -c && ${pkgs.libnotify}/bin/notify-send 'Screenshot saved'";
      # "Shift+Print" = "exec ${pkgs.grim}/bin/grim -c -g $(${pkgs.slurp}/bin/slurp) && ${pkgs.libnotify}/bin/notify-send 'Screenshot saved'";
      # "Ctrl+Shift+Print" = "exec ${pkgs.grim}/bin/grim -c -g $(${pkgs.slurp}/bin/slurp) - | ${pkgs.wl-clipboard}/bin/wl-copy";

      ## Pulse Audio controls
      "XF86AudioRaiseVolume" = "exec --no-startup-id ${
        inputs.volume_control_rs.defaultPackage.${system}
      }/bin/volume_control -- +0.05"; # increase sound volume
      "XF86AudioLowerVolume" = "exec --no-startup-id ${
        inputs.volume_control_rs.defaultPackage.${system}
      }/bin/volume_control -- -0.05"; # decrease sound volume
      "XF86AudioMute" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-sink-mute @DEFAULT_SINK@ toggle"; # mute sound
      "XF86AudioMicMute" = "exec --no-startup-id ${pkgs.pulseaudio}/bin/pactl set-source-mute @DEFAULT_SOURCE@ toggle"; # mute mic audio

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

  # wallpaper
  systemd.user.services.sway-bg = {
    # Reference: https://github.com/nix-community/home-manager/blob/8d5e27b4807d25308dfe369d5a923d87e7dbfda3/modules/programs/waybar.nix#L305
    Unit = {
      Description = "Set sway background";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session-pre.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.swaybg}/bin/swaybg -i ${wallpaper}";
      Restart = "on-failure";
    };
  };
}
