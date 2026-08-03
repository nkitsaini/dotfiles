manifest="${KIT_MUTABLE_CONFIG_MANIFEST:?KIT_MUTABLE_CONFIG_MANIFEST is not set}"

state_root="${XDG_STATE_HOME:-$HOME/.local/state}/kit/mutable-config"

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  color_red=$'\033[1;31m'
  color_green=$'\033[1;32m'
  color_yellow=$'\033[1;33m'
  color_blue=$'\033[1;34m'
  color_magenta=$'\033[1;35m'
  color_cyan=$'\033[1;36m'
  color_reset=$'\033[0m'
else
  color_red=""
  color_green=""
  color_yellow=""
  color_blue=""
  color_magenta=""
  color_cyan=""
  color_reset=""
fi

usage() {
  cat >&2 <<'EOF'
Usage:
  kit config status [name]
  kit config diff [--all] [name]

By default, diff only shows strict entries whose local changes would block
activation. --all also shows safe merge and trackOnly differences.
EOF
}

entries() {
  jq -c '.[]' "$manifest"
}

entry_field() {
  jq -r "$2" <<<"$1"
}

strategy_policy() {
  case "$1" in
    strict)
      printf 'local-edits=rejected'
      ;;
    merge)
      if [[ "${2:-nix}" == live ]]; then
        printf 'local-edits=merged (live wins)'
      else
        printf 'local-edits=merged (nix wins)'
      fi
      ;;
    trackOnly)
      printf 'local-edits=allowed (not managed)'
      ;;
    *)
      printf 'local-edits=unknown'
      ;;
  esac
}

normalise_json() {
  local format="$1"
  local input="$2"
  local output="$3"

  if [[ "$format" == json5 ]]; then
    pyjson5 --as-json "$input" | jq -S . >"$output"
  else
    jq -S . "$input" >"$output"
  fi
}

matches_filter() {
  local entry="$1"
  local filter="$2"
  local name target

  [[ -z "$filter" ]] && return 0
  name="$(entry_field "$entry" '.name')"
  target="$(entry_field "$entry" '.target')"
  [[ "$name" == *"$filter"* || "$target" == *"$filter"* ]]
}

configs_equal() {
  local entry="$1"
  local left="$2"
  local right="$3"
  local strategy format tmp

  strategy="$(entry_field "$entry" '.strategy')"
  format="$(entry_field "$entry" '.mergeFormat')"
  if [[ "$strategy" == merge || "$strategy" == trackOnly ]] && [[ "$format" == json || "$format" == json5 ]]; then
    tmp="$(mktemp -d)"
    if normalise_json "$format" "$left" "$tmp/left" 2>/dev/null \
      && normalise_json "$format" "$right" "$tmp/right" 2>/dev/null \
      && cmp --silent "$tmp/left" "$tmp/right"; then
      rm -rf "$tmp"
      return 0
    fi
    rm -rf "$tmp"
    return 1
  fi

  cmp --silent "$left" "$right"
}

status_state_allowed() {
  local entry="$1"
  local state="$2"
  local source="$3"
  local target="$4"
  local strategy format tmp

  [[ "$state" != modified ]] && return 0

  strategy="$(entry_field "$entry" '.strategy')"
  case "$strategy" in
    strict)
      return 1
      ;;
    trackOnly)
      return 0
      ;;
    merge)
      format="$(entry_field "$entry" '.mergeFormat')"
      tmp="$(mktemp -d)"
      if normalise_json "$format" "$source" "$tmp/source" 2>/dev/null \
        && normalise_json "$format" "$target" "$tmp/target" 2>/dev/null; then
        rm -rf "$tmp"
        return 0
      fi
      rm -rf "$tmp"
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

print_status_line() {
  local state="$1"
  local strategy="$2"
  local allowed="$3"
  local name="$4"
  local icon state_color strategy_color verdict verdict_color

  if [[ "$allowed" == true ]]; then
    verdict="allowed"
    verdict_color="$color_green"
  else
    verdict="blocked"
    verdict_color="$color_red"
  fi

  case "$state:$allowed" in
    identical:*)
      icon="✓"
      state_color="$color_green"
      ;;
    modified:true)
      icon="~"
      state_color="$color_yellow"
      ;;
    modified:false)
      icon="✗"
      state_color="$color_red"
      ;;
    missing:*)
      icon="!"
      state_color="$color_yellow"
      ;;
  esac

  case "$strategy" in
    strict)
      strategy_color="$color_magenta"
      ;;
    merge)
      strategy_color="$color_cyan"
      ;;
    trackOnly)
      strategy_color="$color_blue"
      ;;
    *)
      strategy_color="$color_red"
      ;;
  esac

  printf '%b%s%b  %b%-9s%b  %b%-9s%b  %b%-7s%b  %s\n' \
    "$state_color" "$icon" "$color_reset" \
    "$state_color" "$state" "$color_reset" \
    "$strategy_color" "$strategy" "$color_reset" \
    "$verdict_color" "$verdict" "$color_reset" \
    "$name"
}

show_status() {
  local filter="${1:-}"
  local entry name target source strategy state allowed
  local result=0

  while IFS= read -r entry; do
    matches_filter "$entry" "$filter" || continue
    name="$(entry_field "$entry" '.name')"
    target="$(entry_field "$entry" '.target')"
    source="$(entry_field "$entry" '.source')"
    strategy="$(entry_field "$entry" '.strategy')"

    if [[ ! -e "$target" && ! -L "$target" ]]; then
      state="missing"
    elif configs_equal "$entry" "$source" "$target"; then
      state="identical"
    else
      state="modified"
    fi

    if status_state_allowed "$entry" "$state" "$source" "$target"; then
      allowed=true
    else
      allowed=false
      result=1
    fi
    print_status_line "$state" "$strategy" "$allowed" "$name"
  done < <(entries)

  return "$result"
}

show_diff() {
  local include_safe=false
  local filter=""
  local entry name target source strategy format policy tmp
  local result=0

  while (( $# > 0 )); do
    case "$1" in
      --all)
        include_safe=true
        ;;
      -h|--help)
        usage
        return 0
        ;;
      -*)
        printf 'kit config diff: unknown option: %s\n' "$1" >&2
        usage
        return 2
        ;;
      *)
        if [[ -n "$filter" ]]; then
          printf 'kit config diff: expected at most one name filter\n' >&2
          usage
          return 2
        fi
        filter="$1"
        ;;
    esac
    shift
  done

  while IFS= read -r entry; do
    matches_filter "$entry" "$filter" || continue
    name="$(entry_field "$entry" '.name')"
    target="$(entry_field "$entry" '.target')"
    source="$(entry_field "$entry" '.source')"
    strategy="$(entry_field "$entry" '.strategy')"
    format="$(entry_field "$entry" '.mergeFormat')"
    policy="$(strategy_policy "$strategy" "$(entry_field "$entry" '.mergePriority')")"

    # trackOnly files never participate in activation, so their drift cannot
    # block a rebuild. Merge files still need parsing below: invalid JSON is
    # unsafe even though valid local changes can be merged.
    if [[ "$include_safe" != true && "$strategy" == trackOnly ]]; then
      continue
    fi

    if [[ ! -e "$target" && ! -L "$target" ]]; then
      if [[ "$include_safe" != true && "$strategy" == merge ]]; then
        continue
      fi
      printf 'Missing: %s (%s) [strategy=%s, %s]\n' "$name" "$target" "$strategy" "$policy"
      result=1
      continue
    fi

    if [[ "$strategy" == merge || "$strategy" == trackOnly ]] && [[ "$format" == json || "$format" == json5 ]]; then
      tmp="$(mktemp -d)"
      if ! normalise_json "$format" "$source" "$tmp/nix"; then
        printf 'kit config: Nix source for %s is not valid %s\n' "$name" "$format" >&2
        rm -rf "$tmp"
        result=2
        continue
      fi
      if ! normalise_json "$format" "$target" "$tmp/live"; then
        printf 'kit config: live file for %s is not valid %s: %s\n' "$name" "$format" "$target" >&2
        rm -rf "$tmp"
        result=2
        continue
      fi
      if ! diff -u --label "nix:$name" --label "live:$target" "$tmp/nix" "$tmp/live" >"$tmp/diff"; then
        if [[ "$include_safe" == true || "$strategy" == strict ]]; then
          printf 'Config: %s [strategy=%s, %s]\n' "$name" "$strategy" "$policy"
          cat "$tmp/diff"
          result=1
        fi
      fi
      rm -rf "$tmp"
    else
      tmp="$(mktemp -d)"
      if ! diff -u --label "nix:$name" --label "live:$target" "$source" "$target" >"$tmp/diff"; then
        printf 'Config: %s [strategy=%s, %s]\n' "$name" "$strategy" "$policy"
        cat "$tmp/diff"
        result=1
      fi
      rm -rf "$tmp"
    fi
  done < <(entries)

  return "$result"
}

apply_configs() {
  local check_only="${1:-false}"
  local txn backup_ext backup_overwrite
  local entry id name target source strategy format stage installed dynamic
  local static priority
  local state_dir state_tmp backup
  local -a errors=()

  txn="$(mktemp -d "${TMPDIR:-/tmp}/kit-mutable-config.XXXXXX")"
  backup_ext="${HOME_MANAGER_BACKUP_EXT:-}"
  backup_overwrite="${HOME_MANAGER_BACKUP_OVERWRITE:-}"
  mkdir -p "$txn/staged" "$txn/original" "$txn/changed" "$txn/committed" \
    "$txn/backup-original" "$txn/state-original"

  # Plan and stage every file before touching any target.
  while IFS= read -r entry; do
    id="$(entry_field "$entry" '.id')"
    name="$(entry_field "$entry" '.name')"
    target="$(entry_field "$entry" '.target')"
    source="$(entry_field "$entry" '.source')"
    strategy="$(entry_field "$entry" '.strategy')"
    format="$(entry_field "$entry" '.mergeFormat')"
    stage="$txn/staged/$id"
    installed="$state_root/$id/installed"

    if [[ "$strategy" == trackOnly ]]; then
      continue
    fi

    if [[ ! -f "$source" ]]; then
      errors+=("$name: generated source is not a regular file: $source")
      continue
    fi

    if [[ ( -e "$target" || -L "$target" ) && ! -f "$target" ]]; then
      errors+=("$name: target is not a regular file ($target)")
      continue
    fi

    if [[ -n "$backup_ext" ]]; then
      # Match Home Manager's -b escape hatch: preserve the live file and
      # install the exact Nix value, regardless of the normal strategy.
      cp --dereference "$source" "$stage"
    else
      case "$strategy" in
        strict)
          if [[ ! -e "$target" && ! -L "$target" ]]; then
            cp --dereference "$source" "$stage"
          elif [[ -f "$installed" ]] && cmp --silent "$target" "$installed"; then
            cp --dereference "$source" "$stage"
          elif cmp --silent "$target" "$source"; then
            cp --dereference "$source" "$stage"
          else
            errors+=("$name: filesystem contains changes not in Nix ($target)")
            continue
          fi
          ;;
        merge)
          if [[ ! -e "$target" && ! -L "$target" ]]; then
            # Nothing to merge with, so install the source verbatim and keep
            # its comments and formatting instead of jq's normalised output.
            cp --dereference "$source" "$stage"
          else
            dynamic="$txn/dynamic-$id.json"
            static="$txn/static-$id.json"
            priority="$(entry_field "$entry" '.mergePriority')"
            if ! normalise_json "$format" "$target" "$dynamic"; then
              errors+=("$name: cannot parse live $format file ($target)")
              continue
            fi
            # The Nix source is written in the same dialect as the target, so
            # it needs the same parser before jq sees it.
            if ! normalise_json "$format" "$source" "$static"; then
              errors+=("$name: cannot parse Nix $format source ($source)")
              continue
            fi
            if ! jq -S -n --arg priority "$priority" \
              --slurpfile dynamic "$dynamic" --slurpfile static "$static" \
              'if $priority == "live" then $static[0] * $dynamic[0] else $dynamic[0] * $static[0] end' \
              >"$stage"; then
              errors+=("$name: failed to merge live and Nix settings")
              continue
            fi
          fi
          ;;
        *)
          errors+=("$name: unsupported strategy $strategy")
          continue
          ;;
      esac
    fi

    chmod u+w "$stage"
    if [[ -f "$installed" ]]; then
      cp "$installed" "$txn/state-original/$id"
    else
      : >"$txn/state-original/$id.missing"
    fi
    if [[ -e "$target" || -L "$target" ]]; then
      # Semantic comparison for merge, so a live file keeps its comments and
      # formatting when the merge result is equivalent to what is already there.
      # A symlink is always replaced, since the point is to own a real file.
      if [[ ! -L "$target" ]] && configs_equal "$entry" "$stage" "$target"; then
        continue
      fi
      cp -a --no-dereference "$target" "$txn/original/$id"
    else
      : >"$txn/original/$id.missing"
    fi
    : >"$txn/changed/$id"

    if [[ -n "$backup_ext" && ( -e "$target" || -L "$target" ) ]]; then
      backup="$target.$backup_ext"
      if [[ -e "$backup" || -L "$backup" ]]; then
        if [[ -z "$backup_overwrite" ]]; then
          errors+=("$name: backup already exists ($backup)")
          continue
        fi
        cp -a --no-dereference "$backup" "$txn/backup-original/$id"
      fi
    fi
  done < <(entries)

  if (( ${#errors[@]} > 0 )); then
    printf 'kit.mutableConfig: filesystem contains changes not in Nix, or staging failed:\n' >&2
    printf '  - %s\n' "${errors[@]}" >&2
    printf '\nRun: kit config diff\n' >&2
    if [[ -z "$backup_ext" ]]; then
      printf 'Use kit rebuild -b <extension>, or Home Manager -b <extension>, to replace changed files while keeping backups.\n' >&2
    fi
    rm -rf "$txn"
    return 1
  fi

  if [[ "$check_only" == true ]]; then
    rm -rf "$txn"
    return 0
  fi

  rollback() {
    local rollback_entry rollback_id rollback_target rollback_backup rollback_state_dir
    while IFS= read -r rollback_entry; do
      rollback_id="$(entry_field "$rollback_entry" '.id')"
      rollback_target="$(entry_field "$rollback_entry" '.target')"

      if [[ -e "$txn/committed/$rollback_id" ]]; then
        rm -f -- "$rollback_target"
        if [[ -e "$txn/original/$rollback_id.missing" ]]; then
          :
        elif [[ -e "$txn/original/$rollback_id" || -L "$txn/original/$rollback_id" ]]; then
          cp -a --no-dereference "$txn/original/$rollback_id" "$rollback_target"
        fi

        if [[ -n "$backup_ext" ]]; then
          rollback_backup="$rollback_target.$backup_ext"
          rm -f -- "$rollback_backup"
          if [[ -e "$txn/backup-original/$rollback_id" || -L "$txn/backup-original/$rollback_id" ]]; then
            cp -a --no-dereference "$txn/backup-original/$rollback_id" "$rollback_backup"
          fi
        fi
      fi

      if [[ -f "$txn/state-original/$rollback_id" || -e "$txn/state-original/$rollback_id.missing" ]]; then
        rollback_state_dir="$state_root/$rollback_id"
        rm -f -- "$rollback_state_dir/installed"
        if [[ -f "$txn/state-original/$rollback_id" ]]; then
          mkdir -p "$rollback_state_dir"
          cp "$txn/state-original/$rollback_id" "$rollback_state_dir/installed"
        fi
      fi
    done < <(entries)
  }

  commit_entry() {
    local commit_entry_json="$1"
    local commit_id commit_target commit_stage commit_dir commit_tmp commit_backup

    commit_id="$(entry_field "$commit_entry_json" '.id')"
    [[ -e "$txn/changed/$commit_id" ]] || return 0
    commit_target="$(entry_field "$commit_entry_json" '.target')"
    commit_stage="$txn/staged/$commit_id"
    commit_dir="$(dirname "$commit_target")"
    mkdir -p "$commit_dir"
    : >"$txn/committed/$commit_id"

    if [[ -n "$backup_ext" && ( -e "$commit_target" || -L "$commit_target" ) ]]; then
      commit_backup="$commit_target.$backup_ext"
      if [[ -n "$backup_overwrite" ]]; then
        rm -f -- "$commit_backup"
      fi
      cp -aL -- "$commit_target" "$commit_backup"
    fi

    commit_tmp="$(mktemp "$commit_dir/.kit-config.XXXXXX")"
    cp --dereference "$commit_stage" "$commit_tmp"
    chmod u+w "$commit_tmp"
    mv -fT -- "$commit_tmp" "$commit_target"
  }

  while IFS= read -r entry; do
    if ! commit_entry "$entry"; then
      rollback
      rm -rf "$txn"
      printf 'kit.mutableConfig: commit failed; restored previously changed targets\n' >&2
      return 1
    fi
  done < <(entries)

  update_state_entry() {
    local state_entry_json="$1"
    id="$(entry_field "$state_entry_json" '.id')"
    strategy="$(entry_field "$state_entry_json" '.strategy')"
    [[ "$strategy" == trackOnly ]] && return 0
    stage="$txn/staged/$id"
    [[ -f "$stage" ]] || return 0
    state_dir="$state_root/$id"
    mkdir -p "$state_dir"
    state_tmp="$(mktemp "$state_dir/.installed.XXXXXX")"
    cp "$stage" "$state_tmp"
    chmod u+w "$state_tmp"
    mv -fT "$state_tmp" "$state_dir/installed"
  }

  # Record exactly what was installed, so strict files can distinguish a new
  # Nix value from user drift on the next activation.
  while IFS= read -r entry; do
    if ! update_state_entry "$entry"; then
      rollback
      rm -rf "$txn"
      printf 'kit.mutableConfig: state update failed; restored changed targets\n' >&2
      return 1
    fi
  done < <(entries)

  rm -rf "$txn"
}

command="${1:-}"
case "$command" in
  status)
    shift
    show_status "${1:-}"
    ;;
  diff)
    shift
    show_diff "$@"
    ;;
  __apply)
    apply_configs false
    ;;
  __check)
    apply_configs true
    ;;
  *)
    usage
    exit 2
    ;;
esac
