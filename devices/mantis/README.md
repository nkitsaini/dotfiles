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

## Triggering a sync from Tasker

1. In Tasker, create or open a task and add an action.
2. Choose **Plugin → Termux:Tasker**, then tap its configuration pencil.
3. Select `mantis-sync` from `~/.termux/tasker/`.
4. Set the argument to `all` to sync every enabled repository, or to a Mantis
   repository ID/name to sync only that repository.
5. Save the action and run the task. A successful action means the local daemon
   accepted the request; synchronization continues in the background.

The equivalent command in Termux is:

```console
~/.termux/tasker/mantis-sync all
~/.termux/tasker/mantis-sync termux_notes
```

The wrapper is needed because Termux:Tasker launches approved executables from
`~/.termux/tasker`. It forwards to the daemon's localhost trigger API, so Tasker
and web requests share the same debounce queue.

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
