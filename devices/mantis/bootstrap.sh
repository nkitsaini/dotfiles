#!/data/data/com.termux/files/usr/bin/bash
# Termux SSH bootstrap — safe to run multiple times (idempotent).
set -euo pipefail

PUBKEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDnnPLI8nQHQRfJBU8VALLURlVja5LtrvqF/6Y1gCujI ankit@archlinux"
SSH_PORT=8022
SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"
SOURCES_LIST="$PREFIX/etc/apt/sources.list"

echo "==> Ensuring a package mirror is configured"
# termux-change-repo is an interactive picker; this is the non-interactive
# equivalent of its "Termux (default)" option (official CDN endpoint).
if ! grep -q "^deb .*termux-main" "$SOURCES_LIST" 2>/dev/null; then
    echo "deb https://packages.termux.dev/apt/termux-main stable main" > "$SOURCES_LIST"
fi
apt update -y

echo "==> Installing packages"
pkg install -y openssh termux-services git curl ca-certificates termux-api

TERMUX_API_APK="$(/system/bin/pm path com.termux.api 2>/dev/null || true)"
if [ -z "$TERMUX_API_APK" ]; then
    echo "WARNING: The Termux:API Android companion app is not installed." >&2
    echo "Background Mantis notifications will not work until it is installed" >&2
    echo "from the same source/signing family as Termux and opened once." >&2
fi

echo "==> Configuring Git author"
git config --global user.name "Ankit Saini"
git config --global user.email "nnkitsaini@gmail.com"

echo "==> Adding public key (skipped if already present)"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
grep -qxF "$PUBKEY" ~/.ssh/authorized_keys || echo "$PUBKEY" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "==> Configuring sshd"
ssh-keygen -A   # generates any missing host keys; silently skips existing ones

# Rewrite these directives in place if present (no-op if already correct)
sed -i \
    -e "s/^#\?Port .*/Port ${SSH_PORT}/" \
    -e "s/^#\?PasswordAuthentication .*/PasswordAuthentication no/" \
    -e "s/^#\?PubkeyAuthentication .*/PubkeyAuthentication yes/" \
    "$SSHD_CONFIG"

# Append directives only if the file never had that line at all
grep -q "^Port ${SSH_PORT}$" "$SSHD_CONFIG"              || echo "Port ${SSH_PORT}" >> "$SSHD_CONFIG"
grep -q "^PasswordAuthentication no$" "$SSHD_CONFIG"     || echo "PasswordAuthentication no" >> "$SSHD_CONFIG"
grep -q "^PubkeyAuthentication yes$" "$SSHD_CONFIG"      || echo "PubkeyAuthentication yes" >> "$SSHD_CONFIG"

echo "==> Enabling sshd as a supervised service (auto-restart if killed)"
# Load the service supervisor into this session if it isn't active yet
[ -f "$PREFIX/etc/profile.d/start-services.sh" ] && source "$PREFIX/etc/profile.d/start-services.sh"

if [ ! -L "$PREFIX/var/service/sshd" ]; then
    sv-enable sshd
fi

# runsvdir needs a moment to notice a newly-enabled service and create its
# supervise/ control files before "sv up" can talk to it. Poll instead of
# racing ahead (avoids the "supervise/ok: file does not exist" warning).
for i in $(seq 1 10); do
    [ -e "$PREFIX/var/service/sshd/supervise/ok" ] && break
    sleep 1
done

sv up sshd 2>/dev/null || echo "Note: sshd should start within a few seconds on its own; check with 'sv status sshd'."

echo "==> Done. sshd is supervised on port ${SSH_PORT} and will auto-restart if killed."

echo "==> Installing Mantis repository sync"
MANTIS_RELEASE_REPOSITORY="${MANTIS_RELEASE_REPOSITORY:-nkitsaini/dotfiles}"
MANTIS_RELEASE_BASE="https://github.com/${MANTIS_RELEASE_REPOSITORY}/releases/latest/download"
MANTIS_LOCAL_BINARY="${MANTIS_LOCAL_BINARY:-}"
MANTIS_ARCH="$(uname -m)"
case "$MANTIS_ARCH" in
    aarch64|arm64) MANTIS_ASSET="mantis-aarch64-linux-android.tar.gz" ;;
    *)
        echo "Unsupported Android architecture: $MANTIS_ARCH (Mantis currently ships ARM64 releases)." >&2
        exit 1
        ;;
esac

MANTIS_TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$MANTIS_TMP_DIR"' EXIT
if [ -n "$MANTIS_LOCAL_BINARY" ]; then
    if [ ! -f "$MANTIS_LOCAL_BINARY" ]; then
        echo "MANTIS_LOCAL_BINARY is not a file: $MANTIS_LOCAL_BINARY" >&2
        exit 1
    fi
    echo "==> Using local Mantis binary: $MANTIS_LOCAL_BINARY"
    cp "$MANTIS_LOCAL_BINARY" "$MANTIS_TMP_DIR/mantis"
else
    curl --fail --location --retry 4 --retry-all-errors \
        "${MANTIS_RELEASE_BASE}/${MANTIS_ASSET}" \
        --output "${MANTIS_TMP_DIR}/${MANTIS_ASSET}"
    curl --fail --location --retry 4 --retry-all-errors \
        "${MANTIS_RELEASE_BASE}/${MANTIS_ASSET}.sha256" \
        --output "${MANTIS_TMP_DIR}/${MANTIS_ASSET}.sha256"
    (
        cd "$MANTIS_TMP_DIR"
        sha256sum --check "${MANTIS_ASSET}.sha256"
        tar -xzf "$MANTIS_ASSET"
    )
fi

MANTIS_BIN="$PREFIX/bin/mantis"
MANTIS_BACKUP="$PREFIX/bin/mantis.previous"
install -m 755 "$MANTIS_TMP_DIR/mantis" "${MANTIS_BIN}.new"
if [ -x "$MANTIS_BIN" ]; then
    cp -p "$MANTIS_BIN" "$MANTIS_BACKUP"
fi
mv "${MANTIS_BIN}.new" "$MANTIS_BIN"

echo "==> Configuring Mantis service"
MANTIS_SERVICE="$PREFIX/var/service/mantis"
mkdir -p "$MANTIS_SERVICE"
touch "$MANTIS_SERVICE/down"
printf '%s\n' \
    '#!/data/data/com.termux/files/usr/bin/sh' \
    'exec 2>&1' \
    'exec /data/data/com.termux/files/usr/bin/mantis serve' \
    > "$MANTIS_SERVICE/run.new"
mv "$MANTIS_SERVICE/run.new" "$MANTIS_SERVICE/run"
chmod 700 "$MANTIS_SERVICE/run"
for _ in $(seq 1 10); do
    [ -e "$MANTIS_SERVICE/supervise/ok" ] && break
    sleep 1
done
sv-enable mantis

mkdir -p "$HOME/.termux/tasker" "$HOME/.termux/boot"
chmod 700 "$HOME/.termux" "$HOME/.termux/tasker" "$HOME/.termux/boot"
printf '%s\n' \
    '#!/data/data/com.termux/files/usr/bin/sh' \
    'set -eu' \
    'case "${1:-all}" in' \
    '  all) exec curl --fail --silent --show-error -X POST -H "Content-Type: application/json" -H "X-Mantis-Trigger: 1" -d "{}" http://127.0.0.1:47831/api/public/sync-all ;;' \
    '  *) exec curl --fail --silent --show-error -X POST -G -H "Content-Type: application/json" -H "X-Mantis-Trigger: 1" --data-urlencode "repository=$1" http://127.0.0.1:47831/api/public/sync ;;' \
    'esac' \
    > "$HOME/.termux/tasker/mantis-sync"
chmod 700 "$HOME/.termux/tasker/mantis-sync"
printf '%s\n' \
    '#!/data/data/com.termux/files/usr/bin/sh' \
    '. /data/data/com.termux/files/usr/etc/profile.d/start-services.sh' \
    > "$HOME/.termux/boot/start-services"
chmod 700 "$HOME/.termux/boot/start-services"

echo "==> Restarting Mantis with the newly installed executable"
if ! sv restart mantis; then
    echo "Mantis could not be restarted; restoring the previous executable." >&2
    if [ -x "$MANTIS_BACKUP" ]; then
        cp -p "$MANTIS_BACKUP" "$MANTIS_BIN"
        sv restart mantis 2>/dev/null || true
    fi
    exit 1
fi
MANTIS_HEALTHY=false
for _ in $(seq 1 20); do
    if curl --silent --fail http://127.0.0.1:47831/health >/dev/null; then
        MANTIS_HEALTHY=true
        break
    fi
    sleep 1
done
if [ "$MANTIS_HEALTHY" != true ]; then
    echo "Mantis failed its health check; restoring the previous executable." >&2
    if [ -x "$MANTIS_BACKUP" ]; then
        cp -p "$MANTIS_BACKUP" "$MANTIS_BIN"
        sv restart mantis 2>/dev/null || true
    fi
    exit 1
fi

echo
echo "Mantis is ready. Open this one-time login URL:"
"$MANTIS_BIN" auth-link
echo
echo "Tasker executable: ~/.termux/tasker/mantis-sync (argument: 'all' or a repository ID/name)."
echo "Install and open Termux:API, Termux:Tasker, and Termux:Boot from the same source/signing family as Termux."
