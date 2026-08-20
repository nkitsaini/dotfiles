# Mantis Termux device setup

`bootstrap.sh` configures this Android device's Termux environment. It is safe to
run repeatedly and performs two jobs:

- configures the existing key-only SSH service on port 8022;
- installs the latest checksum-verified Mantis ARM64 release, its runit service,
  Termux:Boot hook, and `~/.termux/tasker/mantis-sync` shell wrapper.

Install Termux and the Termux:API, Termux:Tasker, and Termux:Boot companion apps
from the same distribution/signing source before running the script. Open each
companion app once and grant Tasker its “Run commands in Termux” permission.

Run `./bootstrap.sh`, then open the one-time Mantis URL printed at the end.

## Triggering a sync or backup from Tasker

1. In Tasker, create or open a task and add an action.
2. Choose **Plugin → Termux:Tasker**, then tap its configuration pencil.
3. Select `mantis-sync` or `mantis-backup` from `~/.termux/tasker/`.
4. For `mantis-sync`, set the argument to `all` or a repository ID/name.
5. Save the action and run the task. The local daemon accepts the request and runs the job in the background.

The equivalent commands in Termux are:

```console
# Repository sync
~/.termux/tasker/mantis-sync all

# Restic device backup
~/.termux/tasker/mantis-backup
```

## Restic Backup

Mantis includes direct support for managing and triggering Restic backups on Android.
- Open the Mantis Web UI and navigate to the **Backup** tab.
- Configure repository URL (e.g. `sftp:box-interactive:/home/backups/mantis/restic`), password, hostname (default `mantis`), and backup paths (`/sdcard/Download`, `/sdcard/DCIM`, etc.).
- Use the Web UI or CLI (`mantis backup trigger`, `mantis backup snapshots`) to manage backups.

To test a locally built binary without publishing a release, copy it to the
phone and point bootstrap at it:

```console
# Development machine, after the Nix build:
scp -P 8022 softwares/mantis/result-mantis-android/bin/mantis \
  PHONE_HOST:~/mantis-local

# Termux on the phone:
MANTIS_LOCAL_BINARY="$HOME/mantis-local" ./bootstrap.sh
```

This skips only the GitHub release download. Bootstrap still installs the binary
atomically, configures the services and Tasker wrapper, runs the health check,
and restores the previous executable if startup fails.

The application source and independent Nix build live in `softwares/mantis`.

