# Generic interactive/automated debugging VM: boots a real device NixOS config
# in QEMU (overriding only the hardware/disk/boot/secret bits that can't work in
# a VM) and brings up its graphical session (compositor + bar + notifications +
# theme via the shared home-manager config), so runtime behaviour can be
# verified visually - fire commands, edit live config, hot-reload, screenshot.
#
# Reusable both ways:
#   nix build .#checks.x86_64-linux.vm-debug                 (automated; smoke test + screenshots to ./result)
#   nix run   .#checks.x86_64-linux.vm-debug.driverInteractive  (manual REPL)
#
# For the interactive loop (boot once, iterate without rebuild/reboot) and the
# tips/gotchas, see .agents/skills/nixos-vm-testing/SKILL.md.
{
  pkgs,
  lib,
  inputs,
  system,
  home-manager,
  nur,
  disko,
}:
let
  # Same cli-helpers test fix as flake.nix (the node builds its own pkgs below).
  cliHelpersOverlay = final: prev: {
    python313Packages = prev.python313Packages.overrideScope (
      pyFinal: pyPrev: {
        cli-helpers = pyPrev.cli-helpers.overridePythonAttrs { doCheck = false; };
      }
    );
  };
in
pkgs.testers.runNixOSTest {
  name = "vm-debug";

  # Let the node build its own nixpkgs (with the device's allowUnfree + overlays)
  # rather than reusing the flake's read-only pkgs, so core.nix's
  # `nixpkgs.config` doesn't collide with the framework's read-only nixpkgs.
  node.pkgsReadOnly = false;

  # ./devices/monkey expects these specialArgs (normally provided by mkSystem).
  node.specialArgs = {
    inherit inputs system;
    hostname = "monkey";
    username = "kit";
  };

  nodes.machine =
    { config, lib, pkgs, ... }:
    {
      imports = [
        home-manager.nixosModules.home-manager
        inputs.nur.modules.nixos.default
        disko.nixosModules.disko
        inputs.kit.nixosModules.default
        ../devices/monkey
      ];

      # These monkey modules can't work in the test VM (real disk layout, EFI,
      # and a wireguard key file that doesn't exist). The test framework provides
      # its own root filesystem and boot.
      disabledModules = [
        ../devices/monkey/hardware-configuration.nix
        ../devices/monkey/disko.nix
        ../devices/monkey/wireguard.nix
      ];

      # Node builds its own pkgs (node.pkgsReadOnly = false above); supply the
      # same overlays monkey normally gets via mkSystem. allowUnfree comes from
      # core.nix. kit's home-manager modules need the kit shared modules.
      nixpkgs.overlays = [
        inputs.nur.overlays.default
        cliHelpersOverlay
      ];
      home-manager.sharedModules = [ inputs.kit.hm.default ];

      # --- Make the config boot inside QEMU ---
      boot.loader.systemd-boot.enable = lib.mkForce false;
      boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

      # Bypass greetd/tuigreet: autologin kit on tty1 and exec its home-manager
      # sway (installed via home-manager.useUserPackages into the per-user
      # profile). Keeps the real theme + bar/notification config so bugs
      # reproduce. Force a bash login shell so loginShellInit runs.
      services.greetd.enable = lib.mkForce false;
      services.getty.autologinUser = lib.mkForce "kit";
      # users/kit customizes getty (prompt-only-password via --skip-login), which
      # runs an interactive `login` and defeats autologin. Reset those so
      # autologinUser actually performs a passwordless login on tty1.
      services.getty.loginOptions = lib.mkForce null;
      services.getty.extraArgs = lib.mkForce [ ];
      users.mutableUsers = lib.mkForce true;
      users.users.kit.hashedPassword = lib.mkForce null;
      users.users.kit.password = "test";
      users.users.kit.shell = lib.mkForce pkgs.bashInteractive;
      programs.bash.loginShellInit = lib.mkForce ''
        if [ "$(id -u)" = "1000" ] && [ "$(tty)" = "/dev/tty1" ]; then
          export XDG_RUNTIME_DIR="/run/user/$(id -u)"
          exec /etc/profiles/per-user/kit/bin/sway
        fi
      '';

      # Software rendering (no GPU accel in the VM) + a GPU device sway can use.
      environment.variables.WLR_RENDERER = "pixman";
      virtualisation.qemu.options = [ "-vga none -device virtio-gpu-pci" ];
      virtualisation.memorySize = 6144;
      virtualisation.cores = 4;
      virtualisation.diskSize = 12288;

      environment.systemPackages = with pkgs; [
        grim
        libnotify
      ];
    };

  # Generic harness. The helpers are top-level so they work both headlessly
  # (`nix build .#checks…vm-debug`) and from the interactive REPL. The automated
  # run is a smoke test (session comes up + desktop screenshot); real debugging
  # happens through the VM_INTERACTIVE control loop below.
  testScript = ''
    import shlex

    def kit(cmd, check=True):
        """Run a command as user kit inside the graphical session."""
        env = (
            "export XDG_RUNTIME_DIR=/run/user/1000 "
            "WAYLAND_DISPLAY=wayland-1 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; "
        )
        full = "su - kit -c " + shlex.quote(env + cmd)
        return machine.succeed(full) if check else machine.execute(full)[1]

    def sh(label, cmd):
        machine.log(f"===== {label} =====\n" + kit(cmd, check=False))

    def shot(name):
        machine.screenshot(name)

    def apply_file(path, content):
        """Replace a (read-only, store-symlinked) config file with a writable
        copy so it can be edited live; caller hot-reloads / restarts the app."""
        b64 = __import__("base64").b64encode(content.encode()).decode()
        kit(f"rm -f {path}", check=False)
        kit(f"echo {b64} | base64 -d > {path}", check=False)

    def boot():
        """Bring the VM up to a ready graphical session."""
        start_all()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_file("/run/user/1000/wayland-1", timeout=240)
        machine.sleep(15)
        machine.screenshot("00_desktop")

    boot()
    sh("graphical-session", "systemctl --user list-units --no-pager 2>&1 | grep -iE 'graphical|sway|bar|notif' || true")

    # Interactive control loop: with VM_INTERACTIVE=1 (running the driver binary
    # directly, outside the nix sandbox) read python snippets from a host FIFO
    # and exec them against the *same live VM* - no rebuild, no reboot. `nix
    # build` runs in a clean sandbox where the var is unset, so it just finishes.
    import os as _os
    if _os.environ.get("VM_INTERACTIVE"):
        import traceback as _tb
        _ctrl = _os.environ.get("VM_CTRL", "/tmp/vm_ctrl")
        _n = 0
        machine.log("<<<INTERACTIVE READY>>>")
        while True:
            with open(_ctrl) as _f:
                _code = _f.read()
            if _code.strip() == "__QUIT__":
                break
            _n += 1
            print(f"<<<BEGIN {_n}>>>", flush=True)
            try:
                exec(compile(_code, "<ctrl>", "exec"), globals())
            except Exception:
                _tb.print_exc()
            print(f"<<<END {_n}>>>", flush=True)
  '';
}
