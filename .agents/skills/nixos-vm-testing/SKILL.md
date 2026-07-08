---
name: nixos-vm-testing
description: Boot this repo's NixOS/home-manager config in a QEMU VM to verify runtime behavior (GUI/Wayland, systemd services, session wiring) that a build/eval can't catch, and iterate on it interactively - send commands, edit live config, hot-reload, and screenshot without rebuilding or rebooting. Use when a config change needs a running system to verify, when tuning GUI/CSS/theme visuals, when reproducing a runtime bug, or when writing/running `nixosTest` checks (`nix build .#checks...` / `driverInteractive`).
---

# NixOS VM Testing (interactive + automated)

Build/eval (`fix-flake-build`) catches type/eval/shellcheck errors but not *runtime* behavior: whether a service actually starts, whether a Wayland panel renders, whether CSS looks right. For that, boot the config in a QEMU VM with `pkgs.testers.runNixOSTest`. `/dev/kvm` on the dev box makes boots ~40-60s.

One test definition serves both modes:
- **Automated** (CI / regression): `nix build .#checks.<system>.<name>` runs the `testScript` headlessly and fails the build on a failed assertion. Screenshots land in `result/` when you pass `-o` (see harness below).
- **Interactive** (development / debugging): drive a live VM, run commands, screenshot on demand. This is the high-value loop for visual/GUI work.

Write helper functions at the top level of `testScript` so both modes use the same code.

## The test file

This repo already ships a ready harness: **`tests/vm-debug.nix`**, wired as **`checks.x86_64-linux.vm-debug`**. It boots a real device config with its graphical session and includes the `kit()`/`boot()`/`apply_file()` helpers and the interactive control loop below. Use it directly for most debugging; copy it to `tests/<name>.nix` (and add a `checks.<system>.<name>` entry) only when you need a materially different node config.

A check lives at `tests/<name>.nix` and is wired in `flake.nix` as `checks.<system>.<name>`. To boot a *real* device config (not a throwaway machine), import the device module and disable what can't work in a VM. Key knobs learned the hard way:

```nix
pkgs.testers.runNixOSTest {
  name = "<name>";
  node.pkgsReadOnly = false;          # let the node build pkgs (allowUnfree/overlays from your config)
  node.specialArgs = { inherit inputs system; hostname = "<dev>"; username = "<user>"; };
  nodes.machine = { pkgs, lib, ... }: {
    imports = [ /* hm module, nur, disko, kit, ../devices/<dev> */ ];
    disabledModules = [ /* hardware-configuration.nix, disko.nix, wireguard.nix - real disk/EFI/secrets */ ];
    boot.loader.systemd-boot.enable = lib.mkForce false;
    services.greetd.enable = lib.mkForce false;         # bypass greeter
    services.getty.autologinUser = lib.mkForce "<user>"; # autologin tty1, then exec the compositor
    environment.variables.WLR_RENDERER = "pixman";       # software render (no GPU in VM)
    virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
    virtualisation.memorySize = 6144; virtualisation.cores = 4;
  };
  testScript = '' ... '';
}
```

For a GUI session, autologin on tty1 and `exec` the compositor from the login shell (`/etc/profiles/per-user/<user>/bin/<compositor>`), exporting `XDG_RUNTIME_DIR`. Run per-user commands via `su - <user> -c` with `XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY`, and `DBUS_SESSION_BUS_ADDRESS` exported (wrap this in a `kit()`-style helper in the testScript).

## Persistent interactive VM (boot once, iterate many)

`driverInteractive` gives a Python REPL but needs a TTY. To drive it from non-interactive tooling, add an **env-gated control loop** to `testScript`: it reads Python snippets from a host FIFO and `exec`s them against the *same live VM*. Gated on an env var so `nix build` (clean sandbox) skips it and completes normally.

```python
# end of testScript, after your boot()/baseline
import os as _os, traceback as _tb
if _os.environ.get("VM_INTERACTIVE"):
    _ctrl = _os.environ.get("VM_CTRL", "/tmp/vm_ctrl"); _n = 0
    machine.log("<<<INTERACTIVE READY>>>")
    while True:
        with open(_ctrl) as _f: _code = _f.read()
        if _code.strip() == "__QUIT__": break
        _n += 1; print(f"<<<BEGIN {_n}>>>", flush=True)
        try: exec(compile(_code, "<ctrl>", "exec"), globals())
        except Exception: _tb.print_exc()
        print(f"<<<END {_n}>>>", flush=True)
```

Launch the driver directly (override the wrapper's `--interactive`), backgrounded, output to a log, screenshots to a dir:

```bash
DRV=$(nix build --no-link --print-out-paths '.#checks.x86_64-linux.vm-debug.driverInteractive')
mkfifo /tmp/vm_ctrl; : > /tmp/vm.log
VM_INTERACTIVE=1 VM_CTRL=/tmp/vm_ctrl setsid "$DRV/bin/nixos-test-driver" \
  --no-interactive -o "$PWD/tests/vm-out" >/tmp/vm.log 2>&1 &
# wait for "<<<INTERACTIVE READY>>>" in /tmp/vm.log
```

Synchronous "send code, wait, print output" helper (source once; shell state persists across calls):

```bash
vmcmd() {  # usage: vmcmd 'python code'
  local before after
  before=$(grep -c '<<<END' /tmp/vm.log 2>/dev/null); before=${before:-0}
  printf '%s' "$1" > /tmp/vm_ctrl                 # each echo opens+closes the FIFO -> one read
  for _ in $(seq 1 240); do
    after=$(grep -c '<<<END' /tmp/vm.log 2>/dev/null); after=${after:-0}
    [ "$after" -gt "$before" ] && break; sleep 0.5
  done
  sed 's/\x1b\[[0-9;]*m//g' /tmp/vm.log | awk '/<<<BEGIN/{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}'
}
```

Shut down cleanly with `printf '__QUIT__' > /tmp/vm_ctrl` (the loop breaks, `testScript` ends, the driver tears down the VM) - far better than force-killing QEMU.

## Iterate on live config without rebuilding

home-manager symlinks config into the read-only store. To change it live: replace the symlink with a writable copy, edit, then hot-reload the app instead of rebuilding.

```python
def apply_file(path, content):   # path in the guest, e.g. ~/.config/<app>/style.css
    b64 = __import__("base64").b64encode(content.encode()).decode()
    kit(f"rm -f {path}", check=False)                         # drop the store symlink
    kit(f"echo {b64} | base64 -d > {path}", check=False)      # fresh writable file
```

Hot-reload rather than restart when the app supports it (e.g. `swaync-client --reload-css`, waybar `pkill -USR2 waybar`); otherwise `systemctl --user restart <unit>`. If you instead *append* to an existing writable copy, `chmod u+rw` it first - `cp -L` of a store file keeps the read-only mode and the write fails silently.

Ship any non-trivial payload (CSS, JSON edits, multi-line scripts) as **base64**, or write a host `.py` file and `exec(open("/path").read(), globals())`. Nested quoting through `bash -> su -> python -> heredoc` will bite you otherwise.

## Screenshots

`machine.screenshot("name")` writes `name.png` to the `-o` dir; read it back to actually see the result and self-verify (don't tune visuals blind). Zoom small regions (a bar, one widget) with imagemagick - a full 2556px screenshot hides detail:

```bash
convert shot.png -gravity SouthEast -crop 220x24+0+0 +repage -scale 500% zoom.png
# or: identify -format '%wx%h' shot.png   # real res != the downscaled preview
```

For images with rich fields (icons/actions/urgency), generate representative test data in the guest (e.g. `notify-send -a App -A key=Label -u critical ...`) rather than assuming defaults.

## Gotchas (each cost real time)

- **A blocking guest command hangs the whole driver.** `machine.succeed` waits for exit on a shared serial shell; one command that never returns wedges every later command. Wrap interactive/foreground commands in `timeout N ...` or background them (`... &`). The FIFO loop then stops reading - recover by force-killing and rebooting.
- **`pgrep -f qemu-system` matches your own shell wrapper** (its argv contains the string), giving phantom process counts. Match on `comm` (`pgrep -x`, `ps -eo pid,comm`) or a unique arg like `-name <machine>`.
- **PUA / Nerd-Font glyphs get stripped** when written through editor tooling, silently becoming empty strings. Inject real codepoints with Python (`"\uf0f3"`) or `printf '\xef\x83\xb3'`, then verify with `hexdump -C`.
- **Software rendering only.** Expect `MESA/Vulkan ... failed` log noise and `WLR_RENDERER=pixman`; fine for layout/CSS, not GPU/vulkan/video-decode behavior.
- **Fidelity gap.** A NixOS VM can't reproduce a standalone-home-manager-on-Ubuntu host (nixGL, `genericLinux`, snapd, `/usr/bin` overrides). It faithfully covers shared home-manager modules and full NixOS configs.
- **Use `wait_for_unit` / `wait_for_file` / retries**, not fixed `sleep`, for anything asynchronous (session start, socket creation).
