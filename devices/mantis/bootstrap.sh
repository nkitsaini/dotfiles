#!/data/data/com.termux/files/usr/bin/bash
# Termux SSH bootstrap — safe to run multiple times (idempotent).
set -euo pipefail

PUBKEY="ssh-ed25519 AAAA... your-laptop-key-here"
SSH_PORT=8022
SSHD_CONFIG="$PREFIX/etc/ssh/sshd_config"

echo "==> Installing packages"
pkg install -y openssh termux-services

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
sv up sshd 2>/dev/null || true   # idempotent: no-op if already running

echo "==> Done. sshd is supervised on port ${SSH_PORT} and will auto-restart if killed."
