---
name: fix-flake-build
description: Build (never switch) any device in this dotfiles flake — every `homeConfigurations.*` and `nixosConfigurations.*`, or just one when the user names it — iterate on build failures until each target exits 0, and document every fix that alters runtime behavior with a standardized greppable comment block. Use when the user asks to build, validate, smoke-test, fix, or "unbreak" the configuration for one or all devices, or before they intend to run `home-manager switch` / `nixos-rebuild switch`.
---

# Fix the flake build for a device (or every device)

Iteratively make `nix build` exit 0 for each target. By **default** the skill builds every flake output below; if the user names one device, scope to just that target.

## Targets in this flake

Repo root: `/home/asaini/code/dotfiles`. Always work from here.

| Kind | Target attribute | Build command (no switch) |
|---|---|---|
| Standalone home-manager | `homeConfigurations.<name>.activationPackage` | `nix build /home/asaini/code/dotfiles#homeConfigurations.<name>.activationPackage --show-trace` (or `home-manager build --flake /home/asaini/code/dotfiles/#<name> --show-trace`) |
| NixOS system | `nixosConfigurations.<name>.config.system.build.toplevel` | `nix build /home/asaini/code/dotfiles#nixosConfigurations.<name>.config.system.build.toplevel --show-trace` |

Current devices (cross-check against `flake.nix` if a new one was added):

- `homeConfigurations`: `shifu`, `shifu_remote`
- `nixosConfigurations`: `monkey`, `iso`, `deepak`, `akanksha`, `oogway`, `crane`

Any fix that changes what the user actually gets at runtime MUST be annotated with the `HM-BUILD-FIX` comment template (step 4) so the regression is visible, greppable, and reviewable.

## Hard rules

- **Only `build`, never `switch`.** Never run `home-manager switch`, `nixos-rebuild switch`, `nixos-rebuild boot`, or `nix profile install`. The skill must not mutate the live profile.
- **Never run `nix flake update`** as a "fix". Lock churn is not a build fix; it changes every input at once and hides the real regression. (Updating the lock is a separate workflow — see the `update-flake-and-build-all` skill.)
- **Never delete code silently.** Behavior-changing removals are commented out (with the annotation block), never erased, so the next reviewer can restore them.
- **Never `git add` / `git commit` / `git push`** unless the user explicitly asks.
- Run from the repo root: `/home/asaini/code/dotfiles`.
- **Stay inside the target's own files.** If the user scoped you to one device, never edit another device's `devices/<other>/...` to fix this build. Shared modules under `modules/`, `packages/`, `softwares/` are fair game when the failure is genuinely shared — but say so in the report.
- Hard cap: **5 fix iterations per failing target.** If a target is still failing, stop on that target, record it as unresolved, and move on to the next one. Do not keep guessing.

## Workflow

Track progress:

```
- [ ] 1. Resolve target set
- [ ] 2. Baseline build (all targets in one pass, --keep-going)
- [ ] 3. For each failure: classify → fix → annotate → re-build (≤5 iter)
- [ ] 4. Report
```

### 1. Resolve the target set

- If the user named a device (e.g. "fix shifu", "build monkey"), the target set is just that one.
- Otherwise, the target set is **every** `homeConfigurations.*` and `nixosConfigurations.*` listed above.
- If `flake.nix` defines a target not listed above, include it too. `nix flake show --json /home/asaini/code/dotfiles 2>/dev/null` is the source of truth when in doubt.

### 2. Baseline build

Build all targets in one `nix build` invocation with `--keep-going` so a single broken target doesn't hide the others. `--show-trace` is mandatory; without it nix often hides the actual offending file:line. `tee` so you can re-grep the log without re-running the (slow) build.

Example (all devices):

```bash
nix build --show-trace --keep-going --no-link \
  /home/asaini/code/dotfiles#homeConfigurations.shifu.activationPackage \
  /home/asaini/code/dotfiles#homeConfigurations.shifu_remote.activationPackage \
  /home/asaini/code/dotfiles#nixosConfigurations.monkey.config.system.build.toplevel \
  /home/asaini/code/dotfiles#nixosConfigurations.iso.config.system.build.toplevel \
  /home/asaini/code/dotfiles#nixosConfigurations.deepak.config.system.build.toplevel \
  /home/asaini/code/dotfiles#nixosConfigurations.akanksha.config.system.build.toplevel \
  /home/asaini/code/dotfiles#nixosConfigurations.oogway.config.system.build.toplevel \
  /home/asaini/code/dotfiles#nixosConfigurations.crane.config.system.build.toplevel \
  2>&1 | tee /tmp/hm-build.log
```

Single device variant:

```bash
nix build --show-trace --no-link \
  /home/asaini/code/dotfiles#homeConfigurations.shifu.activationPackage \
  2>&1 | tee /tmp/hm-build.log
```

For standalone home-manager configs you can equivalently use `home-manager build --flake /home/asaini/code/dotfiles/#<name> --show-trace` — pick whichever produces the cleaner error trace for that target.

If every target exits 0, skip to step 4 — there is nothing to fix.

### 3. For each failing target: classify, fix, annotate, re-build

Process targets **one at a time**. For each failing target:

#### 3a. Classify the failure

Read the **last** `error:` frame for *that target's* derivation chain. Nix prints errors bottom-up; the deepest `error:` is the cause. The first one is usually the user-facing wrapper ("build of '.#homeConfigurations.<name>...' failed" or "build of '.#nixosConfigurations.<name>...' failed"), not the root cause.

When `--keep-going` was used, errors for different targets are interleaved — grep with the target's attribute path to isolate its trace:

```bash
rg -n -B2 -A60 'homeConfigurations\.<name>|nixosConfigurations\.<name>' /tmp/hm-build.log
```

Common classes:

| Symptom in log | Class | Typical fix | Behavior-changing? |
|---|---|---|---|
| `attribute '<x>' missing` on `pkgs.<x>` | package renamed/removed in nixpkgs | rename / replace | No, if equivalent name exists |
| `Package '<x>-<ver>' ... is marked as broken` | upstream marked broken | drop or `allowBroken` | **Yes** |
| `Package '<x>' has an unfree license` | unfree not allowed | `allowUnfreePredicate` for that package | **Yes** (scope-dependent) |
| `Package '<x>' is marked as insecure` | CVE flag | `permittedInsecurePackages` | **Yes** |
| `collision between '...' and '...'` | two packages own the same path | `home.file.<path>.force = true` or drop one | **Yes** if dropping |
| `infinite recursion encountered` | module evaluation cycle | break the cycle, preserve logic | No |
| `The option '<x>' does not exist` | option renamed/removed in home-manager / nixos | migrate to new option | No, if migration is 1:1 |
| `hash mismatch in fixed-output derivation` | bad/stale hash | update hash to the one nix reports | No |
| `error: builder for '...' failed with exit code` | build of a dep failed | usually upstream; drop the package or pin | **Yes** if dropping |
| `assertion '...' failed` | a module's assertion tripped | satisfy the assertion | Depends |

If none match, open the offending `.nix` file at the line number from the trace and reason from the source.

#### 3b. Apply the minimal fix

Prefer fixes in this order:

1. **Behavior-preserving** (typo, missing `import`, option rename, hash bump, evaluation-cycle break) — apply directly, no annotation needed.
2. **Behavior-changing but scoped** (drop one package from `home.packages` / `environment.systemPackages`, disable one service, add to `permittedInsecurePackages`) — apply *and* annotate per step 3c.
3. **Cross-cutting** (would touch another device's config, requires a refactor across modules, requires bumping `flake.lock`) — **stop and ask the user instead of attempting it.**

Keep the diff as small as possible. Comment out, don't delete.

#### 3c. Annotate behavior-changing fixes

Every fix that changes what the resulting environment provides MUST be preceded by this exact block, inline in the `.nix` file. The `HM-BUILD-FIX` prefix is the greppable token — do not vary it (keep it even for NixOS-config fixes so a single `rg` surfaces every regression).

```nix
# HM-BUILD-FIX(YYYY-MM-DD): <one-line summary of the change>
# Device(s): <comma-separated device names this affects, or "all">
# Blocks: <what the user no longer gets, or what behavior changed>
# Reason: <the actual error or upstream condition that forced this>
# Revisit-when: <concrete, checkable trigger to re-enable>
```

Rules for the block:

- `YYYY-MM-DD` is today's date.
- `Device(s)` names the affected devices so a multi-device fix is traceable back to who lost what.
- `Revisit-when` MUST be a **checkable** condition, not "later" or "when fixed". Good examples:
  - `nixpkgs-unstable bumps slack >= 4.43.0`
  - `upstream NixOS/nixpkgs#312345 is merged`
  - `after next successful` `` `nix flake update` ``
  - `when home-manager option` `` `programs.foo.bar` `` `is reintroduced`
- Place the block on the line(s) **immediately above** the changed/commented code, at the same indentation.
- If you comment out code, keep the original line(s) below the block (still commented) so intent is recoverable.

Grep convention to enumerate every outstanding regression:

```bash
rg -n 'HM-BUILD-FIX' /home/asaini/code/dotfiles
```

##### Example

Before:

```nix
home.packages = [
  pkgs.slack
  pkgs.foo
];
```

After (slack is marked broken upstream this week, affects shifu and shifu_remote):

```nix
home.packages = [
  # HM-BUILD-FIX(2026-05-27): drop slack from home.packages
  # Device(s): shifu, shifu_remote
  # Blocks: Slack desktop client is no longer installed for the user.
  # Reason: `pkgs.slack` evaluation fails with "marked as broken" on the current nixpkgs pin.
  # Revisit-when: after next `nix flake update` bumps nixpkgs past NixOS/nixpkgs#XXXXXX, or upstream un-marks broken.
  # pkgs.slack
  pkgs.foo
];
```

#### 3d. Re-run the build for that target

Re-run only the failing target (faster feedback than the full set):

```bash
nix build --show-trace --no-link \
  /home/asaini/code/dotfiles#<attrPath of failing target> \
  2>&1 | tee -a /tmp/hm-build.log
```

If a new failure appears, loop back to 3a with the new deepest `error:`. Increment the per-target iteration counter — at iteration 5, stop on that target, record it as unresolved, and move to the next failing target.

Once every failing target either passes or is given up at 5 iterations, do a final `--keep-going` pass over the full set to confirm nothing regressed.

### 4. Report

Output:

1. The final `nix build` command, exit code, and path to the log (`/tmp/hm-build.log`).
2. Per-target status table: `target | status (pass / fail / gave-up-at-iter-5) | iterations used`.
3. For successful targets, the `result*` symlink paths printed by `nix build`.
4. List of files changed in this session.
5. Every `HM-BUILD-FIX` block added or touched in this session, with `file:line`, so the user can review each regression before any `switch`.
6. The exact command the user can run later to audit outstanding regressions:

   ```bash
   rg -n 'HM-BUILD-FIX' /home/asaini/code/dotfiles
   ```

7. Explicit next-step prompt per kind of target:
   - Standalone home-manager: "Run `home-manager switch --flake /home/asaini/code/dotfiles/#<name>` when you're ready."
   - NixOS: "Run `sudo nixos-rebuild switch --flake /home/asaini/code/dotfiles/#<name>` on the target host when you're ready."

   Do not run any switch yourself.

## Anti-patterns

- Running any `switch` to "test" the fix — the skill is build-only.
- Bumping `flake.lock` to dodge a single broken package — it churns every input and hides the real cause. (If a lock bump is actually the goal, use the `update-flake-and-build-all` skill.)
- Deleting the offending line without an `HM-BUILD-FIX` block — silently regresses the environment.
- Vague `Revisit-when: later` or `# TODO fix` — defeats the convention. The whole point is that `rg HM-BUILD-FIX` produces an actionable list.
- Quoting the *first* `error:` in the log. Always read the deepest frame for the target you're working on.
- Editing another device (e.g. `devices/<other>/home.nix`) to fix this device's build. If a shared module is at fault, stop and ask.
- Running each device sequentially with a full evaluation per target when one `nix build ... --keep-going` over the whole set would surface all failures in a single pass.
