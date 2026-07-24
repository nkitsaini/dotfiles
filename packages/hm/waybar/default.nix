{ pkgs, ... }:
let
  themeToggleScript = pkgs.writeShellApplication {
    name = "toggle-theme";

    # 1. Define dependencies here so the script can find 'gsettings' and 'pkill'
    runtimeInputs = [
      pkgs.glib
      pkgs.procps
    ];

    # 2. Read the external file content
    text = builtins.readFile ./toggle-theme.sh;
  };

  # Sparkline chart modules (cpu / ram / ping). One script, dispatched by arg.
  # `iputils` gives it `ping`, `gawk` does the arithmetic + markup rendering,
  # `coreutils` provides `mkdir`/`cat`. Waybar's systemd service has a minimal
  # PATH, so these must be declared here.
  metricsGraphScript = pkgs.writeShellApplication {
    name = "waybar-graph";
    runtimeInputs = [
      pkgs.gawk
      pkgs.iputils
      pkgs.coreutils
    ];
    text = builtins.readFile ./graphs.sh;
  };
  graphBin = "${metricsGraphScript}/bin/waybar-graph";
in
{
  programs.waybar = {
    enable = true;

    # TODO: known issues. waybar systemd doesn't stop quickly enough. Which means the next systemd start fails.
    # So, if you close sway and reopen by running `sway` command quick enough, waybar will be missing. But if you wait some time it'll work.
    systemd.enable = true;
    settings.mainBar = {
      "layer" = "top"; # Waybar at top layer
      "position" = "bottom"; # Waybar position (top|bottom|left|right)
      "height" = 24; # Waybar height (to be removed for auto height)
      # Choose the order of the modules
      "modules-left" = [
        "sway/workspaces"
        "sway/mode"
        "sway/scratchpad"
      ];
      "modules-center" = [ ];
      "modules-right" = [
        "mpd"
        "custom/theme"
        "idle_inhibitor"
        "temperature"
        # cpu/memory replaced by the sparkline chart modules below (they still
        # show the live percentage, plus a rolling history graph).
        "custom/cpugraph"
        "custom/ramgraph"
        "network"
        "custom/pinggraph"
        "pulseaudio"
        "backlight"
        "battery"
        "clock"
        "tray"
        "custom/swaync"
      ];
      "keyboard-state" = {
        "numlock" = true;
        "capslock" = true;
        "format" = "{name} {icon}";
        "format-icons" = {
          "locked" = "";
          "unlocked" = "";
        };
      };
      "sway/mode" = {
        "format" = ''<span style="italic">{}</span>'';
      };
      "sway/scratchpad" = {
        "format" = "{icon} {count}";
        "show-empty" = false;
        "format-icons" = [
          ""
          ""
        ];
        "tooltip" = true;
        "tooltip-format" = "{app}= {title}";
      };
      "mpd" = {
        "format" =
          "  {title} - {artist} {stateIcon} [{elapsedTime=%M=%S}/{totalTime=%M=%S}] {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}[{songPosition}/{queueLength}] [{volume}%]";
        "format-disconnected" = " Disconnected";
        "format-stopped" = " {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped";
        "unknown-tag" = "N/A";
        "interval" = 2;
        "consume-icons" = {
          "on" = " ";
        };
        "random-icons" = {
          "on" = " ";
        };
        "repeat-icons" = {
          "on" = " ";
        };
        "single-icons" = {
          "on" = "1 ";
        };
        "state-icons" = {
          "paused" = "";
          "playing" = "";
        };
        "tooltip-format" = "MPD (connected)";
        "tooltip-format-disconnected" = "MPD (disconnected)";
        "on-click" = "mpc toggle";
        "on-scroll-up" = "mpc volume +2";
        "on-scroll-down" = "mpc volume -2";
      };
      "idle_inhibitor" = {
        "format" = "{icon}";
        "format-icons" = {
          "activated" = "";
          "deactivated" = "";
        };
      };
      "tray" = {
        # can this be used for padding?
        # "icon-size"= 21;
        "spacing" = 10;
      };
      "clock" = {
        "format" = "{:%Y-%m-%d %H:%M %a}";
      };
      "cpu" = {
        "format" = "  {usage}%";
        #        "tooltip"= false
      };
      "memory" = {
        "format" = " {}%";
      };
      "temperature" = {
        "thermal-zone" = 2;
        "hwmon-path" = "/sys/class/hwmon/hwmon1/temp1_input";
        "critical-threshold" = 80;
        "format-critical" = "{icon} {temperatureC}°C";
        "format" = "{icon} {temperatureC}°C";
        "format-icons" = [
          ""
          ""
          ""
        ];
      };
      "backlight" = {
        # "device"= "acpi_video1";
        "format" = "{icon} {percent}%";
        "format-icons" = [
          ""
          ""
          ""
          ""
          ""
          ""
          ""
          ""
          ""
        ];
      };
      "battery" = {
        "states" = {
          # "good"= 95;
          "warning" = 30;
          "critical" = 15;
        };
        "format" = "{icon} {capacity}%";
        "format-charging" = " {capacity}%";
        "format-plugged" = " {capacity}%";
        "format-alt" = "{icon} {time}";

        "format-icons" = [
          " "
          " "
          " "
          " "
          " "
        ];
      };
      "network" = {
        "format-wifi" = "  {essid} ({signalStrength}%)";
        "format-ethernet" = "  {ifname}";
        "tooltip-format" = "  {ifname} via {gwaddr}";
        "format-linked" = "  {ifname} (No IP)";
        "format-disconnected" = "Disconnected ⚠ {ifname}";
        "format-alt" = "  {ifname}= {ipaddr}/{cidr}";
      };

      "wireplumber" = {
        "format" = "{icon}  {volume}%";
        "format-muted" = "";
        "on-click" = "pavucontrol";
        "format-icons" = [
          ""
          ""
          ""
        ];
      };
      "pulseaudio" = {
        "format" = "{icon}  {volume}%";
        "format-muted" = " {format_source}";
        "on-click" = "pavucontrol";
        "format-icons" = {
          "default" = [
            ""
            ""
            ""
          ];
        };
      };
      # --- Live sparkline charts (see ./graphs.sh) ------------------------
      # Each polls the shared script with a metric arg and renders a rolling
      # Unicode block chart. `return-type=json` carries the pango-markup text
      # (so per-bar colours render) plus a severity `class` for CSS. `escape`
      # is left false on purpose so the <span> markup is honoured.
      "custom/cpugraph" = {
        "return-type" = "json";
        "exec" = "${graphBin} cpu";
        "interval" = 2;
        "tooltip" = true;
      };
      "custom/ramgraph" = {
        "return-type" = "json";
        "exec" = "${graphBin} ram";
        "interval" = 2;
        "tooltip" = true;
      };
      "custom/pinggraph" = {
        "return-type" = "json";
        "exec" = "${graphBin} ping";
        # 3s: `ping -W1` can block up to a second, so keep some headroom.
        "interval" = 3;
        "tooltip" = true;
      };
      "custom/theme" = {
        "format" = "{}";
        "return-type" = "json";
        # Point this to your script path
        "exec" = "${themeToggleScript}/bin/toggle-theme";
        # Run the script with the 'toggle' argument on click
        "on-click" = "${themeToggleScript}/bin/toggle-theme toggle";
        # The signal number must match the script (RTMIN+8)
        "signal" = 8;
        "interval" = "once";
        "tooltip" = true;
      };
      # SwayNotificationCenter indicator + toggle. `{}` shows the live
      # notification count (from `swaync-client -swb`); left-click toggles the
      # panel, right-click toggles do-not-disturb. Absolute path so waybar's
      # systemd service (minimal PATH) can find the client.
      "custom/swaync" = {
        # Newer waybar rejects positional "{}" mixed with named "{icon}";
        # use the named "{text}" (the notification count from swaync-client).
        "format" = "{icon} {text}";
        # Nerd Font / FontAwesome bell glyphs. These MUST be real codepoints
        # (U+F0F3 filled bell, U+F0A2 outline bell, U+F1F6 bell-slash) - the
        # previous values were accidentally empty strings, so `{icon}` rendered
        # nothing and only the bare count showed.
        "format-icons" = {
          "notification" = "";
          "none" = "";
          "dnd-notification" = "";
          "dnd-none" = "";
          "inhibited-notification" = "";
          "inhibited-none" = "";
          "dnd-inhibited-notification" = "";
          "dnd-inhibited-none" = "";
        };
        "return-type" = "json";
        "exec" = "${pkgs.swaynotificationcenter}/bin/swaync-client -swb";
        "on-click" = "${pkgs.swaynotificationcenter}/bin/swaync-client -t -sw";
        "on-click-right" = "${pkgs.swaynotificationcenter}/bin/swaync-client -d -sw";
        "escape" = true;
        "tooltip" = true;
      };
    };
    style = builtins.readFile ./style.css;
  };
}
