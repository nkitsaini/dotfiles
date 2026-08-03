#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  kit rebuild [--dry-run] [extra rebuild args...]
  kit config status [name]
  kit config diff [--all] [name]
  kit unfreeze <file>...
  kit help

Dotfiles / home-manager helpers for this machine.
EOF
}

do_rebuild() {
  local dry_run=false
  local -a passthrough=()

  while (( $# > 0 )); do
    case "$1" in
      --dry-run)
        dry_run=true
        shift
        ;;
      --)
        shift
        passthrough+=("$@")
        break
        ;;
      -h|--help)
        cat >&2 <<'EOF'
Usage: kit rebuild [--dry-run] [extra rebuild args...]

Runs the machine's configured home-manager / nixos-rebuild switch.
--dry-run only prints the command that would be executed.
EOF
        return 0
        ;;
      *)
        passthrough+=("$1")
        shift
        ;;
    esac
  done

  if [[ -z "${KIT_REBUILD_BIN:-}" || -z "${KIT_REBUILD_PRINT:-}" ]]; then
    printf 'kit rebuild: not configured for this profile\n' >&2
    printf 'Set kit.rebuild.enable / kit.rebuild.attribute in the device home config.\n' >&2
    return 1
  fi

  if [[ "$dry_run" == true ]]; then
    printf '%s' "$KIT_REBUILD_PRINT"
    if (( ${#passthrough[@]} > 0 )); then
      printf ' %q' "${passthrough[@]}"
    fi
    printf '\n'
    return 0
  fi

  exec "$KIT_REBUILD_BIN" "${passthrough[@]}"
}

do_unfreeze() {
  if [ "$#" -eq 0 ]; then
    echo "usage: kit unfreeze <file>...  # make nix-managed files writable for local iteration" >&2
    exit 2
  fi
  for f in "$@"; do
    if [ ! -e "$f" ] && [ ! -L "$f" ]; then
      echo "kit unfreeze: no such file: $f" >&2
      exit 1
    fi
    # Pick a backup name that doesn't clobber an existing one: <file>.bak,
    # then <file>.bak.1, <file>.bak.2, ... on repeated unfreezes.
    bak="$f.bak"
    n=1
    while [ -e "$bak" ] || [ -L "$bak" ]; do
      bak="$f.bak.$n"
      n=$((n + 1))
    done
    # Move the original (symlink or file) aside, then copy its *contents*
    # back (cp -L dereferences a store symlink) as a real writable file.
    mv -- "$f" "$bak"
    cp -L -- "$bak" "$f"
    chmod u+rw -- "$f"
    echo "kit unfreeze: '$f' is now a writable copy (backup at '$bak')"
  done
}

command="${1:-help}"
case "$command" in
  help|-h|--help)
    usage
    ;;
  rebuild)
    shift
    do_rebuild "$@"
    ;;
  config)
    shift
    if [[ -z "${KIT_MUTABLE_CONFIG_BIN:-}" ]]; then
      printf 'kit config: mutable-config helper is unavailable in this build\n' >&2
      exit 1
    fi
    exec "$KIT_MUTABLE_CONFIG_BIN" "$@"
    ;;
  unfreeze)
    shift
    do_unfreeze "$@"
    ;;
  *)
    usage
    exit 2
    ;;
esac
