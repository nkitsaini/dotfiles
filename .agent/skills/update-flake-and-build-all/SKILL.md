---
name: update-flake-and-build-all
description: Run `nix flake update` and build all the targets (don't switch) just `nix build ...` or equivalent home-manager build, and fix all issues. Use when the user asks to update / bump the flake, refresh `flake.lock`, "update and rebuild everything", validate after a flake update, or otherwise wants every `homeConfigurations.*` and `nixosConfigurations.*` in this dotfiles repo to evaluate cleanly against fresh inputs.
---

# Update `flake.lock` and build every target

Mission, verbatim:

> Run `nix flake update` and build all the targets (don't switch) just `nix build ...` or equivalent home-manager build, and fix all issues.

This skill is the **only** workflow allowed to bump `flake.lock` in this repo. Everywhere else (especially `fix-flake-build`) treats lock churn as forbidden, because it changes every input at once and hides the real regression. Here, the churn *is* the change under test.

## Hard rules

- **Only `build`, never `switch`.** Never run `home-manager switch`, `nixos-rebuild switch`, `nixos-rebuild boot`, or `nix profile install`.
- **Never `git add` / `git commit` / `git push`** unless the user explicitly asks. The modified `flake.lock` stays as an unstaged change so the user can review the diff.
- Run from the repo root: `/home/asaini/code/dotfiles`.
- If `nix flake update` itself fails (e.g. unreachable input), stop and report — do not start rewriting `flake.nix` to dodge it.
- If a target is still failing after the `fix-flake-build` per-target iteration cap (5), stop on that target, mark it unresolved, and continue with the rest. Don't roll back `flake.lock` unilaterally; surface the choice to the user.

## Workflow

Track progress:

```
- [ ] 1. Snapshot the current lock
- [ ] 2. Run `nix flake update`
- [ ] 3. Enumerate all targets
- [ ] 4. Build all targets in one pass (--keep-going)
- [ ] 5. Fix every failure via the `fix-flake-build` skill
- [ ] 6. Final clean pass
- [ ] 7. Report
```

### 1. Snapshot the current lock

So the user (and you) can see exactly what moved:

```bash
cp /home/asaini/code/dotfiles/flake.lock /tmp/flake.lock.before
```

### 2. Run `nix flake update`

```bash
cd /home/asaini/code/dotfiles
nix flake update 2>&1 | tee /tmp/flake-update.log
```

Capture the per-input "Updated input '<name>': old → new" lines from the output — they're the changelog the user wants in the final report.

If `nix flake update` exits non-zero, stop here. Do not proceed to builds. Report the error and the offending input.

### 3. Enumerate all targets

The defaults are the full set declared in `flake.nix`:

- `homeConfigurations`: `shifu`, `shifu_remote`
- `nixosConfigurations`: `monkey`, `iso`, `deepak`, `akanksha`, `oogway`, `crane`

If the user added or removed a device since this skill was last updated, prefer the live source of truth:

```bash
nix flake show --json /home/asaini/code/dotfiles 2>/dev/null \
  | jq -r '
      (.homeConfigurations // {} | keys[] | "homeConfigurations." + . + ".activationPackage"),
      (.nixosConfigurations // {} | keys[] | "nixosConfigurations." + . + ".config.system.build.toplevel")
    '
```

### 4. Build all targets in one pass

One `nix build` invocation, `--keep-going` so one broken target doesn't hide the others, `--show-trace` so the real `file:line` is in the log, `--no-link` so we don't litter `result*` symlinks in the repo, and `tee` so the log is re-greppable:

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
  2>&1 | tee /tmp/post-flake-update-build.log
```

For a standalone home-manager config the equivalent `home-manager build --flake /home/asaini/code/dotfiles/#<name> --show-trace` is also acceptable — use whichever produces the cleaner trace for that target.

If the build exits 0 for every target, skip to step 6.

### 5. Fix every failure

For each failing target, follow the `fix-flake-build` skill end-to-end:

- Same classification table (broken / unfree / insecure / collisions / option renames / hash mismatches / …).
- Same minimal-fix preference order: behavior-preserving → behavior-changing+scoped → ask-the-user for cross-cutting.
- **Same `HM-BUILD-FIX(YYYY-MM-DD)` annotation block** for any fix that changes runtime behavior — including for NixOS configs, so a single `rg HM-BUILD-FIX` still surfaces every regression introduced by this lock bump.
- Same per-target cap of 5 fix iterations. If a target is still red after 5, stop on it and continue to the next one.

`Revisit-when` for fixes caused by this lock bump should reference the bump itself, e.g. `Revisit-when: upstream NixOS/nixpkgs#XXXXXX is merged and the next `nix flake update` picks it up`.

### 6. Final clean pass

After all fixable failures are addressed, re-run the full `--keep-going` build from step 4 to confirm nothing regressed and that the previously-green targets are still green against the new lock.

### 7. Report

Output:

1. The lock changelog (the `Updated input '<name>': '<old>' -> '<new>'` lines from `/tmp/flake-update.log`).
2. The final `nix build` command, exit code, and path to the log (`/tmp/post-flake-update-build.log`).
3. Per-target status table: `target | status (pass / fail / gave-up-at-iter-5) | iterations used`.
4. List of files changed in this session (always includes `flake.lock`; may include any `.nix` files touched by step 5).
5. Every `HM-BUILD-FIX` block added or touched in this session, with `file:line`.
6. The audit command:

   ```bash
   rg -n 'HM-BUILD-FIX' /home/asaini/code/dotfiles
   ```

7. The rollback escape hatch, in case the user prefers to revert rather than carry the regressions forward:

   ```bash
   cp /tmp/flake.lock.before /home/asaini/code/dotfiles/flake.lock
   ```

8. Explicit next-step prompt per kind of target (only after the user has reviewed the lock diff and any `HM-BUILD-FIX` blocks):
   - Standalone home-manager: "Run `home-manager switch --flake /home/asaini/code/dotfiles/#<name>` when you're ready."
   - NixOS: "Run `sudo nixos-rebuild switch --flake /home/asaini/code/dotfiles/#<name>` on the target host when you're ready."

   Do not run any switch yourself.

## Anti-patterns

- Updating one input at a time with `nix flake update <input>` and reporting "the flake builds" — that's not what this skill is for. Use the unfiltered `nix flake update` so all inputs move together.
- Running any `switch`. The skill ends at green builds.
- Committing `flake.lock` (or any other file) without an explicit user ask.
- Reverting `flake.lock` silently when a target fails. Surface the unresolved targets to the user and let them choose: keep + annotate, or roll back.
- Skipping a device because "it's not the user's main machine". The whole point is to catch regressions in every device before they're discovered the hard way during a `switch`.
- Building targets one-by-one when a single `--keep-going` pass would surface all failures at once.
