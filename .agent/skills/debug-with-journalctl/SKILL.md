---
name: debug-with-journalctl
description: Investigate boot, login, session, or service-startup problems on Linux using journalctl, systemctl, and the audit log. Use when the user reports slow boot, slow login, hung sessions, services failing to start, slow desktop appearance after greeter, or any "why is X taking so long?" / "what is blocking Y?" question on a systemd system (especially NixOS).
---

# Debugging with journalctl + systemd

A workflow for narrowing a "something is slow / hung / broken at startup" complaint down to a specific unit, dependency, or wrapper script. Optimized for NixOS but works on any systemd distro.

## Workflow

### 1. Anchor the time window first

Before tailing or filtering, identify the exact boot and the exact moment of the symptom. Without this you'll drown in unrelated logs.

```bash
journalctl --list-boots          # pick the boot id of interest, usually 0
journalctl -b 0 | head           # confirm the boot time
last -x reboot | head            # cross-check reboot history
```

Then bracket aggressively with `--since` / `--until` (accepts `"YYYY-MM-DD HH:MM:SS"`, `"1 hour ago"`, etc.).

### 2. Cut the noise before reading

Raw `journalctl -b 0` is dominated by audit and kernel lines. Filter them out into a temp file you can re-grep:

```bash
journalctl -b 0 --since "..." --until "..." --no-pager \
  | rg -v 'audit\[|audit:|kernel:|systemd-tmpfiles' \
  > /tmp/boot.log
```

Then `rg` for the subsystem you suspect (`sway`, `graphical-session`, `pipewire`, `NetworkManager`, etc.) to spot reaches/stops/failures.

### 3. Watch for systemd's tell-tale timeouts

These constants leak the bug class:

| Number you see in logs | Default it matches | Meaning |
|---|---|---|
| ~`1min 30s` / `90s` / `90.X s` | `TimeoutStopSec=90s` | A service ignored SIGTERM, got SIGKILL'd |
| ~`1min 30s` on start | `TimeoutStartSec=90s` | A service hung in startup |
| ~`5min` | `JobTimeoutSec=300s` for some targets | A target couldn't reach all deps |
| `Startup finished in 1min 30.X s` from user@UID | almost always above | The user manager was blocked on one slow unit |

`State 'stop-sigterm' timed out. Killing.` followed by `Failed with result 'timeout'.` is the smoking gun.

### 4. Per-unit and per-user filters

```bash
journalctl -u <unit>                                 # system unit
journalctl --user-unit=<unit> --user                 # user unit (run as that user)
journalctl _SYSTEMD_USER_UNIT=<unit> --user          # alternative for user units
journalctl _PID=<pid> --user                         # everything one process logged
journalctl _COMM=<basename>                          # by binary name (good for short-lived)
```

User-unit logs only show events the user manager itself emitted. Many "Reached target" lines for the **initial** startup don't appear in `--user-unit` output — read the user manager's PID (`systemd[<pid>]`) directly instead.

### 5. Map the unit dependency graph

```bash
systemctl --user cat <unit>                          # full merged unit file + drop-ins
systemctl --user show <unit>                         # all resolved properties
systemctl --user list-dependencies <unit> --all      # forward (what it pulls in)
systemctl --user list-dependencies <unit> --reverse  # backward (who wants it)
```

Pay attention to these directives — they explain "why did X start/stop?":

- `WantedBy=` / `RequiredBy=` (in `[Install]`) — creates symlinks in `*.target.wants/`; the unit auto-starts with the target.
- `PartOf=` — when the named unit stops, this unit stops too. Common cause of "service X was killed when target Y stopped".
- `BindsTo=` — strict version of `PartOf`+`Requires`; lifecycles are tied both ways.
- `After=` / `Before=` — ordering only, **not** a dependency. A unit with only `After=foo` will not pull `foo` in.
- `ConditionEnvironment=WAYLAND_DISPLAY` — service silently skips if env not set. Why some graphical units don't actually start despite being wanted.
- `StopWhenUnneeded=yes` on a target — target stops the moment nothing wants it.

### 6. Look at `systemd-analyze` for the cheap wins

```bash
systemd-analyze                       # firmware/loader/kernel/initrd/userspace breakdown
systemd-analyze blame                 # slowest system services
systemd-analyze --user blame          # slowest user services
systemd-analyze --user                # user-manager startup time
systemd-analyze critical-chain        # critical path through the dependency graph
```

`systemd-analyze blame` is often a one-shot answer for "what is slow at boot".

### 7. Audit log gives you the execve chain

When you need to know *who* started a process, or which wrapper exec'd what:

```bash
journalctl -b 0 _COMM=<name> | rg 'SYSCALL.*exe='
```

Each `EXECVE`/`SYSCALL` audit line has `ppid=`, `pid=`, `comm=`, `exe=`, `tty=`, `ses=`. Same PID exec'ing two different binaries minutes apart = a wrapper script that blocked between exec calls.

Audit logs require root to read (`sudo` / unrestricted sandbox).

### 8. Mind NixOS wrapper chains

A "binary" on NixOS is often:

1. A compiled **C env wrapper** (`makeCWrapper`) — sets `XDG_DATA_DIRS`, `GIO_EXTRA_MODULES`, etc., then exec's `.foo-wrapped`.
2. A **bash wrapper** (`.foo-wrapped`) — runs `extraSessionCommands` / `extraConfig` / sources rc files, then exec's the real binary.
3. The actual upstream binary in `…-unwrapped-<ver>/bin/<name>`.

`file /nix/store/.../bin/<name>` and `cat` (it's a script) reveal what each layer does. Slow startup of "X" can really be slow startup of a wrapper layer above X.

### 9. Common false leads

- **`tailscaled` DNS-fallback churn** at boot looks alarming but is just bootstrap before the network is up. Ignore unless it's the actual subject.
- **`nix-gc` deletions** flooding the journal — also background, can be filtered with `rg -v nix-gc`.
- **`audit:` / `audit[N]:` lines** — almost always noise unless you specifically want syscall tracing.
- **`Time jumped backwards, rotating.`** from journald + chronyd stepping the clock — this is normal post-boot NTP sync, not a bug.

## Reporting findings

When you've found the culprit, present:

1. The exact log line that proved it (with timestamp).
2. The dependency / wrapper chain that explains *why* it happens.
3. The default value that explains *how long* it takes (e.g. "this is `TimeoutStopSec=90s`").
4. The minimal fix, and optionally a defensive secondary fix (e.g. shorten the timeout so the same class of bug can't bite as hard).
