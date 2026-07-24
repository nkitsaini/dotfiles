# Waybar "live-ish" sparkline module. Emits one JSON object (waybar
# return-type=json) for the metric named by $1: cpu | ram | ping.
#
# How the chart works: each invocation appends one fresh sample to a small
# rolling history kept in a state file, trims it to the last CHART_WIDTH, and
# renders it as a Unicode block sparkline (▁▂▃▄▅▆▇█) of *fixed* width (short
# history is left-padded so the module never grows). With waybar's per-module
# interval this gives a scrolling chart of roughly the last CHART_WIDTH*interval
# seconds. Each bar is individually coloured with pango markup by that sample's
# severity, so spikes/outages are visible at a glance without per-char waybar
# CSS (waybar can only colour a whole module via `class`). A short text label
# (CPU/RAM/PING) prefixes each chart so it's obvious which metric it is.
#
# State lives under $XDG_RUNTIME_DIR (tmpfs, per-boot) so history resets on
# reboot and never touches the notes/dotfiles tree.

metric="${1:-cpu}"

state_dir="${XDG_RUNTIME_DIR:-/tmp}/waybar-graphs"
mkdir -p "$state_dir"

# Fixed chart width, in bars. The chart always renders exactly this many bars:
# once there's real history it shows the last CHART_WIDTH samples, and before
# that it's left-padded with dim placeholder bars, so the module width is
# constant from the very first render (it never grows over time). Kept short so
# it stays compact on the bar.
CHART_WIDTH=10

# Host used for the ping metric. A well-known anycast resolver: low latency,
# always up, so a failed ping really does mean *our* link is down.
PING_HOST="1.1.1.1"

# Pango-markup colours (Solarized, to sit on the light bar).
COL_LOW="#657b83"  # base00 - calm/idle
COL_OK="#859900"   # green
COL_WARN="#b58900" # yellow
COL_CRIT="#dc322f" # red

# --- sampling ---------------------------------------------------------------

# CPU busy percentage since the previous invocation. /proc/stat is a set of
# monotonic counters, so a single reading is meaningless; we diff against the
# previous totals stashed in cpu.prev. First run has no baseline -> reports 0.
sample_cpu() {
  # First field is the literal "cpu" label; trailing fields (guest*) are
  # ignored. `_` is used for both so shellcheck treats them as intentional.
  local user nice system idle iowait irq softirq steal
  read -r _ user nice system idle iowait irq softirq steal _ </proc/stat

  local total=$((user + nice + system + idle + iowait + irq + softirq + steal))
  local idle_all=$((idle + iowait))

  local prev="$state_dir/cpu.prev"
  local usage=0
  if [ -f "$prev" ]; then
    local ptotal pidle
    read -r ptotal pidle <"$prev"
    local dtotal=$((total - ptotal))
    local didle=$((idle_all - pidle))
    if [ "$dtotal" -gt 0 ]; then
      usage=$(((dtotal - didle) * 100 / dtotal))
    fi
  fi
  printf '%s %s\n' "$total" "$idle_all" >"$prev"

  # Clamp to [0,100] in case of counter wrap / suspend-resume skew.
  ((usage < 0)) && usage=0
  ((usage > 100)) && usage=100
  printf '%s' "$usage"
}

# Used RAM percentage (MemTotal - MemAvailable). MemAvailable already accounts
# for reclaimable cache, so this matches what tools like `free` call "used".
sample_ram() {
  awk '
    /^MemTotal:/     { total = $2 }
    /^MemAvailable:/ { avail = $2 }
    END {
      if (total > 0) printf "%d", (total - avail) * 100 / total
      else printf "0"
    }
  ' /proc/meminfo
}

# Round-trip time in ms to PING_HOST, or -1 when the ping fails (link down /
# host unreachable). -c1 one probe, -W1 one-second deadline, -n numeric.
sample_ping() {
  local out rtt
  if out=$(ping -n -c1 -W1 "$PING_HOST" 2>/dev/null); then
    rtt=$(printf '%s' "$out" | awk -F'time=' '/time=/{split($2,a," "); print a[1]; exit}')
    if [ -n "$rtt" ]; then
      printf '%.0f' "$rtt"
      return
    fi
  fi
  printf '%s' "-1"
}

# --- rendering --------------------------------------------------------------

# render <width> <cap> <warn> <crit> <values...>
# Builds the fixed-width coloured sparkline. `width` is the total number of bars
# (short histories are left-padded with dim placeholder bars so the chart never
# changes width). `cap` is the value mapped to a full block; `warn`/`crit` are
# the thresholds that flip a bar's colour. A value of -1 is treated as
# "failure" and drawn as a red full block.
render() {
  local width="$1" cap="$2" warn="$3" crit="$4"
  shift 4
  # q holds a single quote so pango span attributes use single quotes -> the
  # resulting text is valid inside the JSON double-quoted string with no
  # further escaping.
  awk -v width="$width" -v cap="$cap" -v warn="$warn" -v crit="$crit" -v q="'" \
    -v c_low="$COL_LOW" -v c_ok="$COL_OK" -v c_warn="$COL_WARN" -v c_crit="$COL_CRIT" '
    BEGIN {
      lv[1]="▁"; lv[2]="▂"; lv[3]="▃"; lv[4]="▄";
      lv[5]="▅"; lv[6]="▆"; lv[7]="▇"; lv[8]="█";
      out=""
      # Left-pad so the chart is always exactly `width` bars wide. The pad is a
      # dim lowest-block so it reads as "no data yet" and the real samples fill
      # in from the right.
      n = ARGC - 1
      for (i = n; i < width; i++)
        out = out "<span foreground=" q c_low q ">" lv[1] "</span>"
      for (i = 1; i < ARGC; i++) {
        v = ARGV[i] + 0
        if (v < 0) {
          # Failure sample: full red block so outages stand out in the chart.
          out = out "<span foreground=" q c_crit q ">" lv[8] "</span>"
          continue
        }
        # Map value -> block height 1..8.
        h = int(v * 8 / cap) + 1
        if (h < 1) h = 1
        if (h > 8) h = 8
        col = c_ok
        if (v >= crit) col = c_crit
        else if (v >= warn) col = c_warn
        else if (v < warn/2) col = c_low
        out = out "<span foreground=" q col q ">" lv[h] "</span>"
      }
      printf "%s", out
    }
  ' "$@"
}

# severity_class <cur> <warn> <crit>  -> ok|warn|crit (for waybar CSS `class`)
severity_class() {
  local cur="$1" warn="$2" crit="$3"
  if [ "$cur" -lt 0 ]; then
    printf 'crit'
  elif [ "$cur" -ge "$crit" ]; then
    printf 'crit'
  elif [ "$cur" -ge "$warn" ]; then
    printf 'warn'
  else
    printf 'ok'
  fi
}

# emit <label> <sparkline> <current-value> <tooltip> <class>
emit() {
  # pango spans use single quotes, and none of the fields contain a double
  # quote or newline, so this is valid JSON without further escaping. The label
  # is plain text (CPU/RAM/PING) so there's no dependency on a font shipping a
  # particular icon glyph.
  printf '{"text": "%s %s %s", "tooltip": "%s", "class": "%s"}\n' \
    "$1" "$2" "$3" "$4" "$5"
}

# --- history bookkeeping ----------------------------------------------------

# push_and_load <metric> <sample>  -> echoes trimmed, space-separated history
push_and_load() {
  local name="$1" sample="$2"
  local hist_file="$state_dir/$name.hist"
  local hist=""
  [ -f "$hist_file" ] && hist=$(cat "$hist_file")
  hist="$hist $sample"
  # Keep only the last CHART_WIDTH tokens.
  # shellcheck disable=SC2086
  set -- $hist
  while [ "$#" -gt "$CHART_WIDTH" ]; do
    shift
  done
  hist="$*"
  printf '%s' "$hist" >"$hist_file"
  printf '%s' "$hist"
}

# --- per-metric drivers -----------------------------------------------------

case "$metric" in
cpu)
  cur=$(sample_cpu)
  hist=$(push_and_load cpu "$cur")
  # shellcheck disable=SC2086
  spark=$(render "$CHART_WIDTH" 100 60 85 $hist)
  cls=$(severity_class "$cur" 60 85)
  val=$(printf '%3d%%' "$cur")
  emit "CPU" "$spark" "$val" "CPU: ${cur}% (last ${CHART_WIDTH} samples)" "$cls"
  ;;
ram)
  cur=$(sample_ram)
  hist=$(push_and_load ram "$cur")
  # shellcheck disable=SC2086
  spark=$(render "$CHART_WIDTH" 100 70 90 $hist)
  cls=$(severity_class "$cur" 70 90)
  val=$(printf '%3d%%' "$cur")
  emit "RAM" "$spark" "$val" "RAM: ${cur}% used (last ${CHART_WIDTH} samples)" "$cls"
  ;;
ping)
  cur=$(sample_ping)
  hist=$(push_and_load ping "$cur")
  # shellcheck disable=SC2086
  spark=$(render "$CHART_WIDTH" 200 60 150 $hist)
  cls=$(severity_class "$cur" 60 150)
  if [ "$cur" -lt 0 ]; then
    val=$(printf '%5s' "down")
    tip="Ping ${PING_HOST}: no reply (link down?)"
  else
    val=$(printf '%5s' "${cur}ms")
    tip="Ping ${PING_HOST}: ${cur}ms (last ${CHART_WIDTH} probes)"
  fi
  emit "PING" "$spark" "$val" "$tip" "$cls"
  ;;
*)
  echo '{"text": "?", "tooltip": "unknown metric", "class": "crit"}'
  ;;
esac
