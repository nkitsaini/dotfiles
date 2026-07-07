# Schedules the desktop color scheme: dark at night, light in the morning.
#
# Design note: this is intentionally a *single, idempotent reconciler* rather than
# two "set dark"/"set light" services. The reconciler reads the *current* time and
# forces the correct scheme, so it converges to the right state no matter how many
# scheduled transitions were missed (long suspend, power-off, clock jumps) or in what
# order the timer catches up. Two fixed-mode timers would both fire on resume after a
# long suspend and race, leaving the scheme in a nondeterministic state.
{ lib, pkgs, ... }:
let
  # Dark mode is active from `darkHour` (evening) until `lightHour` (morning).
  darkHour = 19;
  lightHour = 7;

  # Matches ../waybar/toggle-theme.sh so waybar's theme indicator stays in sync.
  waybarSignal = 8;

  reconcileTheme = pkgs.writeShellApplication {
    name = "reconcile-theme";
    runtimeInputs = [
      pkgs.glib # gsettings
      pkgs.procps # pkill
      pkgs.coreutils # date
    ];
    text = ''
      # gsettings must use the *dconf* GSettings backend to see and mutate the live
      # session store. A systemd --user service does not inherit the session's
      # GIO_EXTRA_MODULES, so without this gsettings falls back to the in-memory
      # backend: reads return a phantom default (never matching the real scheme, so
      # the reconciler thinks "no change" forever) and writes go somewhere the
      # session never reads. Point GIO at dconf's module explicitly.
      export GIO_EXTRA_MODULES="${pkgs.dconf.lib}/lib/gio/modules''${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"

      hour=$(date +%-H)
      if [ "$hour" -ge ${toString darkHour} ] || [ "$hour" -lt ${toString lightHour} ]; then
        scheme="prefer-dark"
      else
        scheme="prefer-light"
      fi

      current=$(gsettings get org.gnome.desktop.interface color-scheme)
      echo "$(date '+%H:%M %Z') hour=$hour -> want $scheme (dark ${toString darkHour}:00-${toString lightHour}:00); current is $current"

      if [ "$current" = "'$scheme'" ]; then
        echo "already $scheme; no change"
      else
        echo "switching $current -> '$scheme'"
        gsettings set org.gnome.desktop.interface color-scheme "$scheme"
        # Nudge waybar so its custom/theme module refreshes immediately.
        pkill -RTMIN+${toString waybarSignal} waybar || true
      fi
    '';
  };
in
{
  systemd.user.services.theme-schedule = {
    Unit.Description = "Reconcile light/dark color scheme with the time of day";
    Service = {
      Type = "oneshot";
      ExecStart = "${reconcileTheme}/bin/reconcile-theme";
    };
    # Reconcile immediately whenever the graphical session comes up (login/resume).
    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.timers.theme-schedule = {
    Unit.Description = "Schedule light/dark color scheme transitions";
    Timer = {
      OnCalendar = [
        "*-*-* ${lib.fixedWidthNumber 2 lightHour}:00:00"
        "*-*-* ${lib.fixedWidthNumber 2 darkHour}:00:00"
      ];
      # Catch up on the most recent missed transition after a power-off/suspend.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
