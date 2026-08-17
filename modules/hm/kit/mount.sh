#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  kit mount [list]
  kit mount android
  kit mount disk <device>
  kit mount unmount <device|path|GIO URI>
  kit mount power-off <device>

Examples:
  kit mount
  kit mount android
  kit mount disk /dev/sdb1
  kit mount unmount /run/media/$USER/PHOTOS
  kit mount power-off /dev/sdb

`list` prints one shell-usable location per line. UDisks-backed filesystems
normally appear below /run/media/$USER; MTP and other GVfs backends appear
below $XDG_RUNTIME_DIR/gvfs. If GVfs has no POSIX/FUSE path for a mount, its
GIO URI is printed instead.
EOF
}

gio_inventory() {
  LC_ALL=C gio mount --list --detail
}

file_uri_to_path() {
  python3 - "$1" <<'PY'
import sys
from urllib.parse import unquote, urlsplit

uri = urlsplit(sys.argv[1])
if uri.scheme != "file" or uri.netloc not in ("", "localhost"):
    raise SystemExit(1)
print(unquote(uri.path))
PY
}

list_mounts() {
  local inventory uri path gvfs_root scheme name
  local -a non_file_uris=() gvfs_paths=()
  declare -A seen=()

  inventory="$(gio_inventory)"

  emit() {
    local location="$1"
    if [[ -n "$location" && -z "${seen[$location]+present}" ]]; then
      seen["$location"]=1
      printf '%s\n' "$location"
    fi
  }

  while IFS= read -r uri; do
    if [[ "$uri" == file://* ]]; then
      if path="$(file_uri_to_path "$uri")"; then
        emit "$path"
      fi
    else
      non_file_uris+=("$uri")
    fi
  done < <(
    awk -F= '/^[[:space:]]*default_location=/ {
      sub(/^[[:space:]]*default_location=/, "")
      print
    }' <<<"$inventory"
  )

  gvfs_root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs"
  if [[ -d "$gvfs_root" ]]; then
    while IFS= read -r -d '' path; do
      gvfs_paths+=("$path")
      emit "$path"
    done < <(find "$gvfs_root" -mindepth 1 -maxdepth 1 -print0)
  fi

  # Normally every MTP/SFTP/SMB mount has a FUSE path above. Preserve the GIO
  # URI as a useful fallback when FUSE is disabled or unavailable.
  for uri in "${non_file_uris[@]}"; do
    scheme="${uri%%:*}"
    path=""
    for path in "${gvfs_paths[@]}"; do
      name="$(basename "$path")"
      if [[ "$name" == "$scheme:"* || "$name" == "$scheme-"* ]]; then
        path="matched"
        break
      fi
      path=""
    done
    if [[ "$path" != matched ]]; then
      emit "$uri"
    fi
  done
}

list_android_paths() {
  local gvfs_root path name
  local found=false

  gvfs_root="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gvfs"
  if [[ -d "$gvfs_root" ]]; then
    while IFS= read -r -d '' path; do
      name="$(basename "$path")"
      if [[ "$name" == mtp:* ]]; then
        printf '%s\n' "$path"
        found=true
      fi
    done < <(find "$gvfs_root" -mindepth 1 -maxdepth 1 -print0)
  fi

  [[ "$found" == true ]]
}

mount_android() {
  local inventory uri output
  local -a uris=()
  local failures=0

  inventory="$(gio_inventory)"
  mapfile -t uris < <(
    awk -F= '/^[[:space:]]*activation_root=mtp:/ {
      sub(/^[[:space:]]*activation_root=/, "")
      print
    }' <<<"$inventory"
  )

  if (( ${#uris[@]} == 0 )); then
    if list_android_paths; then
      return 0
    fi
    printf 'kit mount android: no MTP device detected\n' >&2
    printf 'Unlock the phone and select USB mode "File transfer", then retry.\n' >&2
    return 1
  fi

  for uri in "${uris[@]}"; do
    if ! output="$(LC_ALL=C gio mount "$uri" 2>&1)"; then
      if [[ "$output" != *"already mounted"* ]]; then
        printf 'kit mount android: %s\n' "$output" >&2
        failures=$((failures + 1))
      fi
    fi
  done

  # The FUSE directory is created asynchronously after the GIO mount returns.
  for _ in {1..20}; do
    if list_android_paths; then
      return "$failures"
    fi
    sleep 0.1
  done

  # A valid GIO mount can exist without gvfsd-fuse. In that case the URI is
  # still usable with `gio copy`, `gio list`, etc.
  for uri in "${uris[@]}"; do
    printf '%s\n' "$uri"
  done
  return "$failures"
}

mount_disk() {
  if (( $# != 1 )); then
    printf 'usage: kit mount disk <device>\n' >&2
    return 2
  fi
  if [[ ! -b "$1" ]]; then
    printf 'kit mount disk: not a block device: %s\n' "$1" >&2
    return 1
  fi
  udisksctl mount --block-device "$1"
}

unmount_target() {
  if (( $# != 1 )); then
    printf 'usage: kit mount unmount <device|path|GIO URI>\n' >&2
    return 2
  fi
  if [[ -b "$1" ]]; then
    udisksctl unmount --block-device "$1"
  else
    gio mount --unmount "$1"
  fi
}

power_off_disk() {
  if (( $# != 1 )); then
    printf 'usage: kit mount power-off <device>\n' >&2
    return 2
  fi
  if [[ ! -b "$1" ]]; then
    printf 'kit mount power-off: not a block device: %s\n' "$1" >&2
    return 1
  fi
  udisksctl power-off --block-device "$1"
}

command="${1:-list}"
case "$command" in
  list)
    shift || true
    if (( $# != 0 )); then
      usage
      exit 2
    fi
    list_mounts
    ;;
  android|mtp)
    shift
    if (( $# != 0 )); then
      usage
      exit 2
    fi
    mount_android
    ;;
  disk|block)
    shift
    mount_disk "$@"
    ;;
  unmount|umount)
    shift
    unmount_target "$@"
    ;;
  power-off|eject)
    shift
    power_off_disk "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  /dev/*)
    mount_disk "$command" "${@:2}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
