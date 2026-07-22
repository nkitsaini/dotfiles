# karo

One front-end for every task runner. "karo" is Hindi for "do it".

Go to any repo and run `karo` — it lists every runnable task from whatever
runners the project uses. Then `karo <task>` runs it by delegating to the
real tool.

```
$ karo
just · justfile
  build   compile everything
  test    <filter>

bun · package.json
  dev     vite dev
  build   vite build

$ karo dev              # -> exec `bun run dev`
$ karo just:build       # qualified form when two runners define `build`
$ karo dev --port 3000  # extra args are forwarded
```

## Supported runners

| runner | manifest | list via | run via |
|---|---|---|---|
| just | `justfile` | `just --dump --dump-format json` | `just <task>` |
| bun / npm / pnpm / yarn | `package.json` scripts | manifest | `<pm> run <task>` |
| deno | `deno.json(c)` tasks | manifest | `deno task <task>` |
| go-task | `Taskfile.yml` | `task --list-all --json` | `task <task>` |
| make | `Makefile` | `make -pRrq` database | `make -C <dir> <task>` |
| uv | `pyproject.toml` `[project.scripts]` | manifest | `uv run <task>` |

The package manager for `package.json` is picked from the `packageManager`
field if present, otherwise the lockfile (`bun.lock` > `pnpm-lock.yaml` >
`yarn.lock` > `package-lock.json`), defaulting to bun.

Manifests are discovered by walking up from the current directory (nearest
one wins, per runner). All parsing and execution semantics stay in the
underlying tools — karo only routes; it never re-implements a runner. The
chosen tool replaces the karo process via `exec`, so exit codes, signals and
TTY behavior are the real tool's.

## Design notes

- Ambiguity is explicit: if two runners define `build`, `karo build` errors
  and tells you to run `karo just:build` or `karo bun:build`.
- If a name is unknown but the project has exactly one runner, karo passes it
  through anyway so you get the real tool's own error/suggestions.
- Runner binaries (`just`, `task`, ...) are looked up on `PATH` at runtime and
  are not build dependencies; a missing one only disables that runner.

## Shell completions

Dynamic completions for fish, bash, and zsh live in `completions/` and are
installed by the nix package into the standard vendor directories
(`share/fish/vendor_completions.d`, `share/bash-completion/completions`,
`share/zsh/site-functions`), which nix profiles / home-manager shells pick up
automatically. Task names are produced at completion time by
`karo --complete-tasks`, which emits `name<TAB>description` lines and uses
the qualified `runner:name` form for tasks defined by multiple runners.
Only the first argument is completed; everything after the task name is
forwarded to the task verbatim.

## Build

```
nix build          # from this directory
cargo test         # unit tests (make db parsing, jsonc, pm selection)
```

Wired into the home-manager setup via the root flake input `karo` and
`home.packages` in `packages/hm/setup-medium.nix`.
