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
      "modules-left" = ["sway/workspaces" "sway/mode" "sway/scratchpad" "custom/media"];
      "modules-center" = ["sway/window"];
      "modules-right" = [
        "mpd"
        "idle_inhibitor"
        "temperature"
        "cpu"
        "memory"
        "network"
        "wireplumber"
        "backlight"
        "battery"
        "tray"
        "clock"
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
      "sway/mode" = {"format" = ''<span style="italic">{}</span>'';};
      "sway/scratchpad" = {
        "format" = "{icon} {count}";
        "show-empty" = false;
        "format-icons" = ["" ""];
        "tooltip" = true;
        "tooltip-format" = "{app}= {title}";
      };
      "mpd" = {
        "format" = "  {title} - {artist} {stateIcon} [{elapsedTime=%M=%S}/{totalTime=%M=%S}] {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}[{songPosition}/{queueLength}] [{volume}%]";
        "format-disconnected" = " Disconnected";
        "format-stopped" = " {consumeIcon}{randomIcon}{repeatIcon}{singleIcon}Stopped";
        "unknown-tag" = "N/A";
        "interval" = 2;
        "consume-icons" = {"on" = " ";};
        "random-icons" = {
          "on" = " ";
        };
        "repeat-icons" = {"on" = " ";};
        "single-icons" = {"on" = "1 ";};
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
        "format" = "{:%Y-%m-%d %H:%M}";
      };
      "cpu" = {
        "format" = "  {usage}%";
        #        "tooltip"= false
      };
      "memory" = {"format" = " {}%";};
      "temperature" = {
        "thermal-zone" = 2;
        "hwmon-path" = "/sys/class/hwmon/hwmon1/temp1_input";
        "critical-threshold" = 80;
        "format-critical" = "{icon} {temperatureC}°C";
        "format" = "{icon} {temperatureC}°C";
        "format-icons" = ["" "" ""];
      };
      "backlight" = {
        # "device"= "acpi_video1";
        "format" = "{icon} {percent}%";
        "format-icons" = ["" "" "" "" "" "" "" "" ""];
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
        
        "format-icons" = [" " " " " " " " " "];
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
        "on-click" = "helvum";
        "format-icons" = ["" "" ""];
      };
      "custom/media" = {
        "format" = "{icon} {}";
        "return-type" = "json";
        "max-length" = 40;
        "format-icons" = {
          "spotify" = "";
          "default" = "🎜";
        };
        "escape" = true;
        "exec" = "$HOME/.config/waybar/mediaplayer.py 2> /dev/null";
      };
    };
    style = builtins.readFile ./style.css;
  };
}
