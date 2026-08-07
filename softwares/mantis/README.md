# Mantis

Mantis is a localhost-only Git synchronization service designed for Termux. A
single Rust binary embeds a mobile-first SvelteKit/Tailwind UI and provides the
same synchronization engine to its daemon, web API, and one-shot CLI.

## Behavior

Each sync locks its repository, stages non-binary tracked/untracked changes and
deletions, commits them, fetches the configured remote, merges without rewriting
history, and pushes. Files with a NUL byte in their first 512 bytes remain
unstaged. Diverged histories that conflict are left as a normal Git merge and can
be resolved in the web UI using base/ours/theirs views and an editable result.

Daemon sync requests are debounced per repository. The first request starts
immediately, one follow-up request may remain pending, and further requests are
coalesced into that pending run. Consequently, no repository has more than one
active sync or more than one queued sync. The Activity view records whether a
request was started, queued, or debounced.

Mantis never force-pushes, discards local work, deletes repository data when a
repository is unregistered, or silently accepts an SSH host key.

When a repository is registered, Mantis adds its exact canonical worktree path
to Git's global `safe.directory` list. This is required for worktrees on Android
shared storage, whose files appear to Git as owned by a different UID. Mantis
never enables the wildcard `safe.directory=*`.

State is stored in `~/.local/share/mantis/mantis.db`; rotating JSONL logs live in
`~/.local/state/mantis/mantis.jsonl`. HTTPS tokens and unencrypted dedicated SSH
keys are protected by Termux's Android app sandbox and mode-0600 files.

## Build and development

The Nix flake is the canonical build:

```console
nix build .#default
nix build .#frontend
nix build .#android-aarch64
nix develop
```

### Build the final Termux release locally

From the repository root, build the same Android ARM64 output used by CI:

```console
nix build ./softwares/mantis#android-aarch64 \
  --accept-flake-config \
  --out-link softwares/mantis/result-mantis-android
file softwares/mantis/result-mantis-android/bin/mantis
```

The executable is `softwares/mantis/result-mantis-android/bin/mantis`. To create
the exact files consumed by the bootstrap installer and uploaded by CI:

```console
mkdir -p softwares/mantis/dist/stage
cp softwares/mantis/result-mantis-android/bin/mantis \
  softwares/mantis/dist/stage/mantis
tar -C softwares/mantis/dist/stage -czf \
  softwares/mantis/dist/mantis-aarch64-linux-android.tar.gz mantis
cd softwares/mantis/dist
sha256sum mantis-aarch64-linux-android.tar.gz \
  > mantis-aarch64-linux-android.tar.gz.sha256
sha256sum -c mantis-aarch64-linux-android.tar.gz.sha256
```

To exercise the full installer without a GitHub Actions round trip, copy the
binary to the phone and select it explicitly:

```console
# Development machine:
scp -P 8022 softwares/mantis/result-mantis-android/bin/mantis \
  PHONE_HOST:~/mantis-local

# Termux on the phone, from the dotfiles checkout:
cd devices/mantis
MANTIS_LOCAL_BINARY="$HOME/mantis-local" ./bootstrap.sh
```

The override skips only the release download; bootstrap retains its atomic
install, health check, and rollback. The result symlink and `dist/` are ignored
by Git.

Without Nix:

```console
cd web
bun install --frozen-lockfile
bun run check
bun run build
cd ..
cargo test
cargo run -- serve
```

Frontend dependency changes require regenerating `web/bun.nix` with `bun2nix`.
Release tags named `mantis-v*` cause CI to build and publish the Android ARM64
archive and checksum consumed by `devices/mantis/bootstrap.sh`.

## CLI and automation

```console
mantis auth-link
mantis repo add NAME /path/to/worktree
mantis sync NAME --wait
mantis sync-all --wait
mantis status
```

The CLI runs one-shot and therefore still works when the web daemon is down.
Authenticated management APIs use a long-lived HttpOnly browser session obtained
from a 15-minute, single-use enrollment URL. The only unauthenticated routes are
localhost sync triggers; they require JSON and `X-Mantis-Trigger: 1`:

```console
curl -H 'Content-Type: application/json' -H 'X-Mantis-Trigger: 1' \
  -d '{}' http://127.0.0.1:47831/api/public/sync-all
```

Bootstrap also installs `~/.termux/tasker/mantis-sync`. Select that executable
in a Tasker **Plugin → Termux:Tasker** action and pass `all`, or pass one
repository ID/name. The wrapper calls the daemon's localhost trigger API and
returns once the request is accepted; the sync then runs in the background.

For detached metadata, clone through the UI with a content directory and a
separate Git directory. Existing repositories whose `.git` pointer already uses
detached metadata can be registered directly. Automatic relocation of an
existing `.git` directory is intentionally not performed.
