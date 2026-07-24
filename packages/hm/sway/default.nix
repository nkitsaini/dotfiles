# This is a nixos package (not home-manager)
{
  pkgs,
  config,
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
  # Single launcher for every "open a terminal" path (the Mod+Return bind and
  # rofi's `-terminal`). `+new-window` uses ghostty's D-Bus IPC: it opens a window
  # in the already-running instance (no cold start) and relies on D-Bus activation
  # to start ghostty when nothing is running. This is much faster than plain
  # `ghostty`, which re-reads config, inspects the environment and re-initializes
  # GTK on every launch. Wrapped in a script so the value stays a single token
  # (rofi's `-terminal` expects one executable) and so rofi's appended `-e <cmd>`
  # is forwarded correctly (`+new-window -e` is honored since ghostty 1.3.0). The
  # D-Bus/systemd activation files come from programs.ghostty.systemd.enable (set
  # in the ghostty module). See https://ghostty.org/docs/linux/systemd
  terminal_launcher = pkgs.writeShellScriptBin "ghostty-launch" ''
    exec ${pkgs.ghostty}/bin/ghostty +new-window "$@"
  '';
  terminal_cmd = "${terminal_launcher}/bin/ghostty-launch";

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

  # Routes brightness changes to the display the cursor is on: laptop panel
  # via brightnessctl, external monitors over DDC/CI via ddcutil. Also the
  # CLI for every other monitor setting (monitorctl vcp ...). Same derivation
  # as the one installed by the ../monitorctl import below.
  monitorctl = pkgs.callPackage ../monitorctl/package.nix { };
  # Locking goes through a dedicated systemd user service (defined below)
  # instead of launching gtklock straight from swayidle. Two reasons:
  #   1. swayidle fires the lock command from several places (1200s timeout,
  #      lock event, before-sleep). `systemctl start` on an already-active
  #      service is a no-op, so we get single-instance locking for free and
  #      never end up with stacked lock surfaces (the old symptom where you
  #      had to type the password two or three times).
  #   2. The service runs in its own cgroup. The after-resume handler restarts
  #      swayidle.service to re-arm idle timers (swaywm/swayidle#156); when
  #      gtklock was a child of swayidle that restart killed the locker and
  #      the screen silently unlocked after suspend/resume.
  lock_cmd =
    if disableSwayLock then
      turn_off_output_cmd
    else
      "${pkgs.systemd}/bin/systemctl --user start gtklock.service";
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

  menu = "${nixGLCommandPrefix}${pkgs.rofi}/bin/rofi -terminal ${terminal_cmd} -show drun -show-icons";

  # Theme-aware wallpaper. The desktop background follows the GNOME
  # `color-scheme` gsettings key (the same key the darkmode scheduler and the
  # waybar toggle already drive), so the wallpaper switches together with the
  # rest of the light/dark theme.
  wallpapers = import ../../shared/wallpapers.nix;
  wallpaperLight = wallpapers.wallpaperLight;
  wallpaperDark = wallpapers.wallpaperDark;

  # gsettings inside a `systemd --user` service does not inherit the session's
  # GIO_EXTRA_MODULES, so it silently falls back to the in-memory backend
  # (reads return a phantom default, writes go nowhere). Point GIO at dconf's
  # module explicitly. See the long note in ../darkmode/default.nix.
  gioDconf = ''export GIO_EXTRA_MODULES="${pkgs.dconf.lib}/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"'';

  # Prints the wallpaper path for the *current* color-scheme. Used by the lock
  # screen so gtklock's background matches the active theme at lock time.
  currentWallpaper = pkgs.writeShellApplication {
    name = "current-wallpaper";
    runtimeInputs = [ pkgs.glib ];
    text = ''
      ${gioDconf}
      scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
      if [ "$scheme" = "'prefer-dark'" ]; then
        printf '%s' "${wallpaperDark}"
      else
        printf '%s' "${wallpaperLight}"
      fi
    '';
  };

  # Long-running background daemon: sets the wallpaper immediately, then reacts
  # to every color-scheme change by swapping swaybg. It watches the gsettings
  # key directly, so it stays in sync no matter what flips the theme (the
  # time-of-day reconciler, the waybar toggle, or a manual gsettings set) with
  # no coupling to those components.
  wallpaperDaemon = pkgs.writeShellApplication {
    name = "sway-wallpaper-daemon";
    runtimeInputs = [
      pkgs.glib
      pkgs.swaybg
      pkgs.coreutils
    ];
    text = ''
      ${gioDconf}

      current_pid=""

      set_wallpaper() {
        local scheme img
        scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
        if [ "$scheme" = "'prefer-dark'" ]; then
          img="${wallpaperDark}"
        else
          img="${wallpaperLight}"
        fi

        # Start the new swaybg first, give it a moment to draw, then kill the
        # previous one. Overlapping like this avoids a flash of empty root
        # window during the swap.
        swaybg -i "$img" -m fill &
        local new_pid=$!
        sleep 1
        if [ -n "$current_pid" ]; then
          kill "$current_pid" 2>/dev/null || true
        fi
        current_pid=$new_pid
      }

      set_wallpaper

      # Process substitution (not a pipe) so the loop runs in this shell and
      # `current_pid` persists across events. Wrapped in `while true` so the
      # daemon re-establishes the monitor if `gsettings monitor` ever exits.
      while true; do
        while read -r _; do
          set_wallpaper
        done < <(gsettings monitor org.gnome.desktop.interface color-scheme)
        sleep 2
      done
    '';
  };
in
{

  home.packages = with pkgs; [
    wl-clipboard
    gtklock
    swayidle
    sway_display_control
    xwayland
    grim
    slurp
  ];
  imports = [
    ../../hm/waybar
    ../wlsunset
    ../monitorctl
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

      # For some reason /dev/dri/card0 is a virtual device instead of integrated amd gpu on shifu
      # Use this to identify correct one. It should mention amdgpu or something:
      #       cat /sys/class/drm/cardN/device/uevent
      #       Example: cat /sys/class/drm/card0/device/uevent
      exec env WLR_DRM_DEVICES=/dev/dri/card1 ${nixGLCommandPrefix}sway
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
  services.swayosd.enable = true;

  services.swayidle = {
    enable = true;
    events = {
      "before-sleep" = "${pkgs.playerctl}/bin/playerctl pause; ${lock_cmd}";
      "lock" = lock_cmd;
      # Restart swayidle after every resume. swayidle does not reset its
      # idle timers on wake (swaywm/swayidle#156), so if the system was
      # suspended via the 3600s timeout, the same notification can re-fire
      # immediately on resume and trigger another suspend cycle. Restarting
      # the service re-arms all timers from zero. --no-block so this
      # command returns before systemd kills the current swayidle instance.
      "after-resume" =
        "${turn_on_output_cmd}; ${pkgs.systemd}/bin/systemctl --user --no-block restart swayidle.service";
      "unlock" = turn_on_output_cmd;
    };
    timeouts = [
      {
        timeout = 1200; # Use idlelock on waybar while watching long videos etc.
        command = lock_cmd;
      }
      {
        timeout = 3600;
        command = "${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
  };
  # Notification daemon: swaync (SwayNotificationCenter). Chosen over mako
  # because it renders inline action buttons (e.g. Yes/No prompts) and provides
  # a notification-center / do-not-disturb panel. Only one daemon may own the
  # org.freedesktop.Notifications D-Bus name, so mako is disabled below.
  # Styling is intentionally left to swaync's shipped default stylesheet.
  services.swaync = {
    enable = true;
    settings = {
      layer = "overlay"; # show even over fullscreen windows (mako did the same)
      control-center-layer = "overlay";
      # Timeouts are in seconds here (mako used 10000ms). Keep popups up long
      # enough to actually read (~30s); critical stays until dismissed.
      timeout = 30;
      timeout-low = 30;
      timeout-critical = 0;
      notification-window-width = 420;
      keyboard-shortcuts = true;
      image-visibility = "when-available";
      # Panel open/close slide animation (ms). Default is 200; 0 = instant.
      transition-time = 0;
      widgets = [
        "title"
        "dnd"
        "notifications"
      ];
    };
    # Notification center themed in a muted Nord palette:
    # a soft charcoal (#2e3440) panel with clearly-bordered cards (not pure
    # black + hairlines), off-white text, a calm accent (not a loud blue), and
    # a pill DND toggle.
    #
    # We @import swaync's shipped sheet (via the package path so it tracks
    # updates) only for baseline layout, then override the surfaces heavily.
    # This also fixes the white-background bug: swaync's default gives the
    # focused *group* `--noti-bg-focus`, which rendered as a solid white block
    # whenever >=2 app groups were present; giving cards a solid dark background
    # and forcing group/row focus transparent removes it. All verified visually
    # in the VM debug test (tests/vm-debug.nix).
    style = ''
      @import url("file://${config.services.swaync.package}/etc/xdg/swaync/style.css");

      * {
        font-family: "Noto Sans", "Noto Sans CJK KR", sans-serif;
        /* Make everything feel instantaneous: disable CSS fade/slide
           transitions (group expand/collapse, hover). GtkRevealer slide
           animations are separately disabled via transition-time = 0. */
        transition: none;
      }

      /* ---------- Panel: soft charcoal (Nord polar night), not pure black ---------- */
      .control-center {
        background: #2e3440;
        border: 1px solid #3b4252;
        border-radius: 14px;
        padding: 8px;
        color: #e5e9f0;
      }
      .control-center .control-center-list { background: transparent; }
      .control-center .control-center-list-placeholder { color: #6b7488; }

      /* ---------- Header (title + Clear All) ---------- */
      .widget-title { margin: 6px 8px 8px 8px; }
      .widget-title > label { font-size: 13px; font-weight: bold; color: #8b93a5; }
      .widget-title button {
        background: transparent; color: #8b93a5;
        border: none; box-shadow: none; border-radius: 8px;
        padding: 4px 10px; font-size: 12px;
      }
      .widget-title button:hover { background: #3b4252; color: #eceff4; }

      /* ---------- Do Not Disturb (muted accent, not loud blue) ---------- */
      .widget-dnd { margin: 2px 8px 10px 8px; color: #cdd3df; font-size: 13px; }
      .widget-dnd > switch {
        background: #434c5e; border: none; box-shadow: none;
        border-radius: 999px; min-width: 42px; min-height: 22px;
      }
      .widget-dnd > switch:checked { background: #81a1c1; }
      .widget-dnd > switch slider {
        background: #d8dee9; border-radius: 999px;
        min-width: 18px; min-height: 18px; margin: 2px;
      }
      .widget-dnd > switch:checked slider { background: #eceff4; }

      /* ---------- Cards with clear borders + spacing (clear separation) ---------- */
      .notification-row { background: transparent; outline: none; }
      .notification-row:focus,
      .notification-row:hover,
      .notification-row:selected { background: transparent; }

      .notification-row .notification-background { padding: 4px 4px; }

      .notification-row .notification-background .notification,
      .notification-group.collapsed .notification-row .notification {
        background: #3b4252;
        background-color: #3b4252;
        border: 1px solid #4b5468;
        border-radius: 10px;
        box-shadow: none;
      }

      .notification-row .notification-background .notification .notification-default-action,
      .notification-row .notification-background .notification .notification-default-action:active,
      .notification-row .notification-background .notification .notification-default-action:focus,
      .notification-row:selected .notification-background .notification .notification-default-action,
      .notification-row:focus .notification-background .notification .notification-default-action {
        background: transparent;
        border-radius: 10px;
        padding: 12px 12px;
      }
      .notification-row .notification-background .notification .notification-default-action:hover {
        background: #434c5e;
      }

      /* ---------- Content typography (off-white, not pure white) ---------- */
      .notification-content { background: transparent; }
      .notification-content .app-icon { margin: 0 12px 0 2px; }
      .notification-content .text-box .summary { font-size: 14px; font-weight: bold; color: #eceff4; }
      .notification-content .text-box .time { color: #7b8494; font-size: 12px; }
      .notification-content .text-box .body { color: #aeb6c6; font-size: 13px; }

      /* ---------- Action buttons: soft filled ---------- */
      .notification-action > button {
        background: #434c5e;
        color: #e5e9f0;
        border: 1px solid #4c566a;
        border-radius: 8px;
        box-shadow: none;
        padding: 5px 14px;
        margin: 6px 6px 4px 6px;
      }
      .notification-action > button:hover {
        background: #4c566a; color: #eceff4; border-color: #5e81ac;
      }

      /* ---------- Close buttons ---------- */
      .close-button {
        background: transparent; color: #8b93a5;
        border: none; box-shadow: none; border-radius: 999px; margin: 4px;
      }
      .close-button:hover { background: #bf616a; color: #eceff4; }

      /* ---------- Subtle critical indicator: muted red left accent stripe ----------
         swaync only tags notifications with .low/.normal/.critical here in the
         panel (this urgency is NOT exposed to the waybar module), so a thin
         Nord-aurora-red left border is enough to flag critical without shouting. */
      .notification-row .notification-background .notification.critical {
        border-left: 3px solid #bf616a;
      }

      /* ---------- Groups: blend into the flat list ---------- */
      .notification-group { background: transparent; border-radius: 0; }
      .notification-group:focus { background: transparent; }
      .notification-group .notification-group-headers .notification-group-header {
        color: #8b93a5; font-size: 12px; font-weight: bold;
      }
      .notification-group .notification-group-headers .notification-group-icon {
        -gtk-icon-size: 16px; color: #8b93a5;
      }
      .notification-group .notification-group-buttons button,
      .notification-group .notification-group-close-button .close-button {
        background: transparent; color: #8b93a5;
        border: none; box-shadow: none; border-radius: 8px;
      }
    '';
  };

  # Replaced by swaync above; kept disabled (not deleted) for easy revert.
  services.mako.enable = false;

  wayland.windowManager.sway.enable = true;
  # wayland.windowManager.sway.checkConfig = false; # https://discourse.nixos.org/t/services-xserver-xkb-extralayouts-doesnt-seem-to-be-compatible-with-sway/46128
  wayland.windowManager.sway.systemd.enable = true;
  wayland.windowManager.sway.systemd.variables = [
    "DISPLAY"
    "WAYLAND_DISPLAY"
    "SWAYSOCK"
    "XDG_CURRENT_DESKTOP"
    "XDG_SESSION_TYPE"
    "NIXOS_OZONE_WL"
    "XCURSOR_THEME"
    "XCURSOR_SIZE"
    # Portal-launched apps (e.g. Cursor from cursor:// URLs) and portal
    # services themselves need this to reach the session bus. Without it,
    # screenshare breaks when portals restart mid-session.
    "DBUS_SESSION_BUS_ADDRESS"
  ];
  wayland.windowManager.sway.xwayland = true;
  # Source ~/.xprofile (not ~/.xsession). ~/.xsession is the home-manager X11
  # session entrypoint: it starts hm-graphical-session.target then immediately
  # stops graphical-session.target and busy-loops waiting for units to deactivate.
  # When sourced from the sway wrapper there is no session command to bracket,
  # so the stop fires straight away and the loop pegs at ~90s on any unit that
  # doesn't promptly handle SIGTERM (batsignal in particular). ~/.xprofile only
  # sets up env vars (hm-session-vars.sh, .profile, systemctl import-environment),
  # which is what's actually wanted here. Real session lifecycle is handled by
  # the home-manager sway systemd integration (sway.systemd.enable / variables
  # above) plus sway's own `exec systemctl --user start sway-session.target`.
  wayland.windowManager.sway.extraSessionCommands = ''
    # For some reason, this script is also run while `nixos-rebuild`, when the ~/.xprofile is not available (different fs). So conditional execution.
    # $HOME at that time is /homeless-shelter, which builder uses
    if [ "$HOME" == "${config.home.homeDirectory}" ]; then
      source ${config.home.homeDirectory}/.xprofile
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

      # Brightness: acts on the display the cursor is on. Laptop panel goes
      # through the kernel backlight, external monitors through DDC/CI
      # (see packages/hm/monitorctl; /dev/i2c-* access is required for the
      # DDC path - hardware.i2c.enable on NixOS, devices/shifu/README.md on
      # the Ubuntu host).
      "XF86MonBrightnessUp" = "exec ${monitorctl}/bin/monitorctl brightness up";
      "XF86MonBrightnessDown" = "exec ${monitorctl}/bin/monitorctl brightness down";

      # Screenshot
      "Print" = "exec ${pkgs.grim}/bin/grim -c && ${pkgs.libnotify}/bin/notify-send 'Screenshot saved'";
      # "Shift+Print" = "exec ${pkgs.grim}/bin/grim -c -g $(${pkgs.slurp}/bin/slurp) && ${pkgs.libnotify}/bin/notify-send 'Screenshot saved'";
      # "Ctrl+Shift+Print" = "exec ${pkgs.grim}/bin/grim -c -g $(${pkgs.slurp}/bin/slurp) - | ${pkgs.wl-clipboard}/bin/wl-copy";

      ## Pulse Audio controls
      "XF86AudioRaiseVolume" = "exec --no-startup-id ${
        inputs.volume_control_rs.defaultPackage.${pkgs.stdenv.hostPlatform.system}
      }/bin/volume_control -- +0.05"; # increase sound volume
      "XF86AudioLowerVolume" = "exec --no-startup-id ${
        inputs.volume_control_rs.defaultPackage.${pkgs.stdenv.hostPlatform.system}
      }/bin/volume_control -- -0.05"; # decrease sound volume
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

  # Screen locker as its own service. Started via `systemctl --user start
  # gtklock.service` from swayidle's timeout/lock/before-sleep commands.
  # Living in a separate cgroup is what makes the locker survive both the
  # after-resume swayidle restart and the suspend/resume cycle, so the screen
  # stays locked until the password is actually entered.
  systemd.user.services.gtklock = {
    Unit = {
      Description = "gtklock screen locker";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      # Don't try to lock when there is no Wayland session to lock.
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      Type = "simple";
      # Resolve the wallpaper at lock time so the lock screen matches the
      # current light/dark theme (currentWallpaper reads the live color-scheme).
      ExecStart = pkgs.writeShellScript "gtklock-start" ''
        exec ${pkgs.gtklock}/bin/gtklock -b "$(${currentWallpaper}/bin/current-wallpaper)"
      '';
      # gtklock exits 0 once the user authenticates. Any non-zero exit (e.g.
      # it lost its Wayland connection) means the screen is no longer locked,
      # so bring the locker back rather than leaving the session exposed.
      # A successful unlock does not trigger a restart.
      Restart = "on-failure";
      RestartSec = 1;
    };
  };

  # wallpaper: theme-aware daemon (swaybg + a gsettings color-scheme watcher).
  # Replaces the old static `swaybg -i <fixed>` one-shot so the background can
  # switch with light/dark mode. See wallpaperDaemon in the `let` block above.
  systemd.user.services.sway-bg = {
    # Reference: https://github.com/nix-community/home-manager/blob/8d5e27b4807d25308dfe369d5a923d87e7dbfda3/modules/programs/waybar.nix#L305
    Unit = {
      Description = "Set sway background (theme-aware)";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session-pre.target" ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${wallpaperDaemon}/bin/sway-wallpaper-daemon";
      Restart = "on-failure";
    };
  };
}
