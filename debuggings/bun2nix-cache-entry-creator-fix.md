# Debugging bun2nix-cache-entry-creator symlink error

**What we did:**
1. We encountered a build failure in `bun2nix-cache-entry-creator-2.0.1.drv` (error: `ln: failed to create symbolic link '/p': Permission denied` during `patchPhase`).
2. We traced this dependency to a custom local package at `$HOME/code/dotfiles/softwares/git_syncer`.
3. We updated the local `git_syncer` package by regenerating its `bun.nix` file and updating its local flake lock to point to the `master` branch of `bun2nix`.
4. We realized the top-level flake lock was still caching the old version. We ran `nix flake update` in `$HOME/code/dotfiles`, which successfully bumped the `bun2nix` input from version `2.0.1` to `2.0.8`.
5. We kicked off a new `nixos-rebuild build --flake .#monkey`. We saw that it correctly started building the updated `bun2nix-cache-entry-creator-2.0.8.drv`.

**Files modified:**
- `$HOME/code/dotfiles/softwares/git_syncer/bun.nix` (regenerated)
- `$HOME/code/dotfiles/softwares/git_syncer/flake.lock` (updated inputs)
- `$HOME/code/dotfiles/flake.lock` (updated top-level inputs)

**Conclusion:**
Updating the `bun2nix` input to `2.0.8` resolved the previous symlink permission error in the system build.
