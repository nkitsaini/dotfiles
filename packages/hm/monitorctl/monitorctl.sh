# monitorctl - control brightness (and any DDC/CI setting) of the display
# the cursor is on, laptop panel and external monitors alike.
#
# Routing: sway's focused output == the output the cursor is on (the sway
# config sets focus.followMouse = always). eDP-*/LVDS-*/DSI-* panels are
# driven through the kernel backlight (brightnessctl); everything else is
# assumed to be an external monitor and driven over DDC/CI (ddcutil).
# Nothing here is monitor-specific: the i2c bus is resolved from the DRM
# connector at runtime, so any DDC/CI-capable monitor works.

shopt -s nullglob

# Default step for brightness up/down (percent).
default_step=2

usage() {
  cat <<'EOF'
Usage:
  monitorctl [-o OUTPUT] brightness up [STEP]   # STEP defaults to 2 (percent)
  monitorctl [-o OUTPUT] brightness down [STEP]
  monitorctl [-o OUTPUT] brightness set VALUE   # 0-100
  monitorctl [-o OUTPUT] brightness get
  monitorctl [-o OUTPUT] vcp DDCUTIL_ARGS...    # raw ddcutil against that monitor
  monitorctl list                               # all outputs + how they are controlled

Without -o OUTPUT, the command acts on sway's focused output, i.e. the
display the cursor is on.

Examples:
  monitorctl brightness down          # what the brightness keys run
  monitorctl vcp capabilities         # everything this monitor supports
  monitorctl vcp getvcp ALL           # current values of all settings
  monitorctl vcp setvcp 62 30         # e.g. set speaker volume (VCP 0x62) to 30
EOF
}

die() {
  echo "monitorctl: $*" >&2
  exit 1
}

focused_output() {
  swaymsg -t get_outputs | jq -r '.[] | select(.focused) | .name'
}

is_internal() {
  case "$1" in
    eDP-* | LVDS-* | DSI-*) return 0 ;;
    *) return 1 ;;
  esac
}

# Print the i2c bus number serving a DRM connector (e.g. HDMI-A-1 -> 13).
# Fast path: most drivers (amdgpu, i915, ...) expose the connector's DDC
# channel as a sysfs symlink, so no probing is needed. Fallback: a full
# ddcutil scan (slower, covers DP-MST and drivers without the symlink).
ddc_bus_for() {
  local out=$1
  local dev link
  for dev in /sys/class/drm/card*-"$out"; do
    [ -e "$dev/ddc" ] || continue
    [ "$(cat "$dev/status")" = "connected" ] || continue
    link=$(readlink -f "$dev/ddc")
    echo "${link##*i2c-}"
    return 0
  done
  ddcutil detect --brief 2>/dev/null | awk -v out="$out" '
    $1 == "Display" { bus = "" }
    /I2C bus:/ { bus = $NF; sub(".*i2c-", "", bus) }
    /DRM.?connector:/ && $NF ~ ("-" out "$") && bus != "" { print bus; found = 1; exit }
    END { exit !found }
  '
}

require_ddc_bus() {
  local out=$1
  local bus
  bus=$(ddc_bus_for "$out") ||
    die "no DDC/CI bus found for $out (monitor may have DDC/CI disabled in its OSD; check: ddcutil detect)"
  echo "$bus"
}

# ddcutil's per-invocation DDC/CI verification costs ~250ms, but its answer
# only changes when the physical monitor changes. So: verify for real the
# first time we see a monitor, then remember that via a marker file keyed on
# connector + EDID hash. Per-boot cache (XDG_RUNTIME_DIR); swapping monitors
# changes the EDID hash, so the new monitor gets a full verification again.
cache_dir=${XDG_RUNTIME_DIR:-/tmp}/monitorctl

# Print the marker path identifying the exact monitor on this connector.
# Fails (-> caller falls back to always-verify) if the EDID is unreadable.
ddc_verified_marker() {
  local out=$1
  local dev hash
  for dev in /sys/class/drm/card*-"$out"; do
    [ -e "$dev/edid" ] || continue
    [ "$(cat "$dev/status")" = "connected" ] || continue
    # sysfs binary attributes stat as 0 bytes, so check content, not [ -s ].
    [ "$(wc -c < "$dev/edid")" -gt 0 ] || continue
    hash=$(sha256sum "$dev/edid" | cut -c1-16)
    echo "$cache_dir/ddc-ok-$out-$hash"
    return 0
  done
  return 1
}

cmd_list() {
  local name focused desc via bus marker
  swaymsg -t get_outputs |
    jq -r '.[] | [.name, (.focused | tostring), .make + " " + .model] | @tsv' |
    while IFS=$'\t' read -r name focused desc; do
      if is_internal "$name"; then
        via="laptop backlight (brightnessctl)"
      elif bus=$(ddc_bus_for "$name"); then
        via="ddc/ci on i2c bus $bus (ddcutil --bus $bus)"
      else
        via="no control channel found"
      fi
      marker=" "
      if [ "$focused" = "true" ]; then
        marker="*"
      fi
      printf '%s %-10s %-32s %s\n' "$marker" "$name" "$desc" "$via"
    done
}

output=""
if [ "${1:-}" = "-o" ] || [ "${1:-}" = "--output" ]; then
  [ $# -ge 2 ] || die "-o needs an output name (see: monitorctl list)"
  output=$2
  shift 2
fi

cmd=${1:-}
case "$cmd" in
  list)
    cmd_list
    exit 0
    ;;
  brightness | vcp) ;;
  "" | -h | --help | help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    die "unknown command: $cmd"
    ;;
esac
shift

if [ -z "$output" ]; then
  output=$(focused_output)
fi
[ -n "$output" ] || die "could not determine focused sway output (is sway running?)"

if [ "$cmd" = "vcp" ]; then
  if is_internal "$output"; then
    die "$output is the laptop panel; DDC/CI does not apply"
  fi
  [ $# -ge 1 ] || die "vcp needs ddcutil arguments, e.g.: monitorctl vcp capabilities"
  bus=$(require_ddc_bus "$output")
  exec ddcutil --bus "$bus" "$@"
fi

# cmd = brightness
action=${1:-}
arg=${2:-}
if is_internal "$output"; then
  case "$action" in
    up) exec brightnessctl set "${arg:-$default_step}+%" ;;
    down) exec brightnessctl set "${arg:-$default_step}-%" ;;
    set)
      [ -n "$arg" ] || die "brightness set needs a value (0-100)"
      exec brightnessctl set "$arg%"
      ;;
    get)
      cur=$(brightnessctl get)
      max=$(brightnessctl max)
      echo $((cur * 100 / max))
      ;;
    *)
      usage >&2
      die "unknown brightness action: '$action'"
      ;;
  esac
else
  bus=$(require_ddc_bus "$output")
  # First invocation for a given monitor runs ddcutil's full DDC/CI
  # verification (~360ms); once that has succeeded, later invocations pass
  # --skip-ddc-checks (~110ms per keypress, ~50ms of which is the DDC write
  # itself). mark_verified only runs after a successful DDC operation.
  marker=$(ddc_verified_marker "$output") || marker=""
  skip_checks=()
  if [ -n "$marker" ] && [ -e "$marker" ]; then
    skip_checks=(--skip-ddc-checks)
  fi
  ddc() { ddcutil --bus "$bus" "${skip_checks[@]}" "$@"; }
  # Writes are coalesced: sway repeats a held keybinding at the keyboard
  # repeat rate (50/s here), far faster than a DDC write (~150ms), so without
  # a guard the presses queue up and the ramp keeps going after key release.
  # flock -n drops a press instantly when one is already in flight; with
  # relative steps that just caps the ramp at the speed the bus can do.
  # --noverify skips the write read-back: under a fast ramp the monitor may
  # occasionally ignore a write, but brightness is adjusted by eye, so a
  # dropped step costs nothing and keeps every press fast.
  ddc_write() {
    mkdir -p "$cache_dir"
    flock -n "$cache_dir/lock-$output" \
      ddcutil --bus "$bus" "${skip_checks[@]}" --noverify setvcp "$@"
  }
  mark_verified() {
    if [ -n "$marker" ] && [ ! -e "$marker" ]; then
      mkdir -p "$cache_dir"
      touch "$marker"
    fi
  }
  # VCP feature 0x10 is brightness (MCCS standard, any monitor).
  case "$action" in
    up)
      ddc_write 10 + "${arg:-$default_step}"
      mark_verified
      ;;
    down)
      ddc_write 10 - "${arg:-$default_step}"
      mark_verified
      ;;
    set)
      [ -n "$arg" ] || die "brightness set needs a value (0-100)"
      ddc_write 10 "$arg"
      mark_verified
      ;;
    get)
      # getvcp --brief prints: "VCP 10 C <current> <max>"
      ddc getvcp 10 --brief | awk '{ print $4 }'
      mark_verified
      ;;
    *)
      usage >&2
      die "unknown brightness action: '$action'"
      ;;
  esac
fi
