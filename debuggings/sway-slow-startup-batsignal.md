# Debugging slow sway startup after tuigreet login

**Symptom:**
After entering credentials in tuigreet, the screen stayed on the greeter for ~90s before sway's desktop appeared.

**What we did:**
1. Identified the current boot with `journalctl --list-boots` and ran `journalctl -b 0 --since ... --until ...` around the login moment, filtering audit/kernel/nix-gc noise.
2. Searched the window for `sway|wayland|graphical-session|waybar|swaybg` and found `Reached target sway compositor session` only at 16:58:23, while the kit session opened at 16:56:58 — an 85s gap.
3. Looked at the user manager (PID 3466) log and found `batsignal.service: State 'stop-sigterm' timed out. Killing.` immediately followed by `Startup finished in 1min 30.624s.` — the classic `TimeoutStopSec=90s` signature.
4. Cross-checked with `auditctl`/audit syscall entries: same `sway` PID 3531 exec'd the C wrapper at 16:56:59, then exec'd `sway-unwrapped` 84s later — i.e. the wrapper script blocked, not sway itself.
5. Read the wrapper chain: `…/sway-1.11/bin/sway` (C env wrapper) → `.sway-wrapped` (bash) → `sway-unwrapped`. The bash wrapper sources `~/.xsession`, which is home-manager's **X11 session** entrypoint: it starts `hm-graphical-session.target`, then immediately stops `graphical-session.target` and busy-loops on `--state=deactivating list-units`. With no `eval "$@"` session command in between (sway has no args), the stop fires instantly and batsignal — `Wants=graphical-session.target`, no `ConditionEnvironment=WAYLAND_DISPLAY` — hangs on SIGTERM for the full 90s.
6. Found the offending source in `packages/hm/sway/default.nix`'s `extraSessionCommands` (added in commit `bf64eb0` to import env vars; the user wanted `.xprofile`, not `.xsession`).

**Files modified:**
- `packages/hm/sway/default.nix` — `extraSessionCommands` now sources `~/.xprofile` (env vars only) instead of `~/.xsession` (full X11 session lifecycle).
- `packages/hm/setup-minimal.nix` — added `systemd.user.services.batsignal.Service.TimeoutStopSec = "5s";` as a defensive cap so any future misbehaving teardown of `graphical-session.target` can't block for 90s again.

**Conclusion:**
Wrapper sourced `~/.xsession`, which is X11-session lifecycle code, not env setup. Its post-session cleanup ran at sway startup with nothing to wait on except a freshly-spawned `batsignal` that ignores SIGTERM, pegging at the 90s systemd default. Switching to `~/.xprofile` and capping batsignal's stop timeout removes both the root cause and the worst-case fallback.
