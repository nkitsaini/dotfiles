# markdown-lsp

A high-quality, configurable **Markdown language server** written in Rust.

It focuses on the things that make editing Markdown pleasant:

- **Path completion** inside link and image destinations, **deep and fuzzy**
  (fzf-style, powered by [`nucleo-matcher`]). It searches the whole workspace by
  default, so a nearby file completes without first typing `../`, and chooses the
  link style from the prefix you've typed and `completion.pathStyle`:
  - **bare** (no prefix) — configurable as **relative**, **absolute**, or
    **hybrid** (relative for siblings/children and workspace-root absolute for
    other files). The default, **auto**, selects hybrid in a Git work tree and
    relative elsewhere;
  - **`./` / `../`** — everything is offered **relative** (walking up as needed);
  - **`/`** — everything is offered **absolute** (workspace-root relative).

  Directories re-trigger completion so you can keep narrowing. The walk uses
  ripgrep's `ignore` crate, so it **respects `.gitignore` / `.ignore`** and skips
  hidden files by default (both configurable), and is bounded (depth, a scan
  budget and a result cap) so it stays fast in large trees.
- **Quick `@` / `/` commands**: type a trigger character at the start of a line
  (or after a space) to open a small insert menu, à la Notion/Slack:
  - **dates & times** — `now` (`14:30`), `today` / `tomorrow` / `yesterday`
    (`2026-07-07`) and `datetime` (`2026-07-07 14:30`); formats are
    configurable;
  - **file links** — every workspace file (same deep, fuzzy, workspace-wide
    search as path completion), inserted as an inline link `[stem](path)`, so
    `/gui` becomes `[guide](./docs/guide.md)`.

  Accepting an item replaces the trigger and anything typed after it (`/now` →
  `14:30`). Triggers embedded in words (`and/or`, `a@b.com`) and inside link
  destinations are ignored.
- **Inline-on-demand**: keep your source tidy with reference links (`[t][id]` +
  `[id]: url` at the bottom) but get every link expanded **inline** when you need
  it — references are resolved against the whole document, so a lifted-out
  *selection* is self-contained. Two code actions: **Copy as inlined Markdown**
  (writes the result straight to the system clipboard, buffer untouched) and
  **Convert selection to inline links** (rewrites the selection in place). Also a
  `markdown-lsp inline` CLI subcommand for whole files / stdin.
- **Document links** (`textDocument/documentLink`): link and image destinations
  become clickable — external URLs (`http`, `https`, `mailto`, …) open as-is,
  and existing local files open in the editor.
- **Go to definition / find references** for links:
  - a file link/image (`[t](./a.md)`) jumps to that file (resolving a
    `#heading` fragment to the heading's line);
  - a reference link (`[t][id]` / `[id]`) jumps to its `[id]: url` definition;
  - a `#anchor` link jumps to the matching heading in the document;
  - *find references* lists every `[..][id]` usage of an id, or every link in
    the document pointing at the same file.
- **Table formatting**: normalises GFM tables on format — adds surrounding
  pipes, inserts a missing header separator (and one empty body row), aligns
  columns, turns a stray trailing `|` into a full empty row, and grows the
  separator/body when a new header cell is added.
- **List formatting**: normalises list markers on format — unordered bullets
  (`*` / `+`) become `-`, ordered lists are renumbered to increment from their
  first item's number (`1. 1. 1.` → `1. 2. 3.`), and the gap after a marker
  collapses to a single space (re-indenting continuation lines and nested items
  to match).
- **Reference-link formatting**: convert inline links to reference links and
  consolidate the definitions under a `# References` heading at the bottom of the
  file — and back again. Available as an on-demand code action / command, and
  (optionally) via `textDocument/formatting`.
- **Daily / journal notes**: a command (`openDailyNote`, exposed as *Open
  today's / yesterday's / tomorrow's journal note* code actions) that opens the
  dated note — creating it from a configurable template the first time, like
  `cp journal/template.md journal/2026-07-07.md`, and just opening it thereafter.
- **Folding** at heading/section, list, code-block, block-quote, table and
  front-matter granularity.
- **Broken-link diagnostics**: warns when a link/image points at a local file
  that does not exist.
- **Document outline** (headings) and **hover** (a link's resolved target and
  whether it exists).
- **Project config file**: an optional `.markdown-lsp.json` or
  `.markdown-lsp.jsonc` at the workspace root, deep-merged over the editor's
  settings, so project conventions (journal template, formatting, …) are
  portable across Zed / Neovim / VS Code / the CLI. Both names accept JSONC
  comments and trailing commas.
- A **command-line mode** (`markdown-lsp format` / `inline` / `lint`, accepting
  files *or* directories) so the same formatter and broken-link checker can run
  in scripts and CI.

It speaks standard LSP over stdio, uses **incremental** text synchronisation,
negotiates the position encoding (UTF-8 / UTF-16), and caches per-document
analysis so only edited documents are reparsed.

[`nucleo-matcher`]: https://docs.rs/nucleo-matcher

## Building

### With Nix (recommended)

A `flake.nix` provides the Rust toolchain and builds the binary.

```bash
# Enter a dev shell with cargo/rustc/clippy/rust-analyzer:
nix develop

# ...or build the release binary directly:
nix build
./result/bin/markdown-lsp --help   # CLI help; run with no args to serve LSP over stdio
```

### With Cargo

```bash
cargo build --release
# binary at target/release/markdown-lsp
```

## Editor setup

The server communicates over stdio; point your editor at the `markdown-lsp`
binary for `markdown` documents.

### Neovim (built-in LSP)

```lua
vim.lsp.config.markdown_lsp = {
  cmd = { "/path/to/markdown-lsp" },
  filetypes = { "markdown" },
  root_markers = { ".git" },
  -- Optional settings (see "Configuration" below):
  init_options = {
    formatting = { moveReferencesToBottom = true },
  },
}
vim.lsp.enable("markdown_lsp")
```

### VS Code

Any generic "start an LSP over stdio" extension works; pass the binary path as
the server command and `markdown` as the document selector. Settings can be sent
either as `initializationOptions` or via `workspace/didChangeConfiguration`.

### Zed

Zed has no built-in Markdown language server and only lets `lsp.<key>.binary`
point at server keys it already recognizes, so the trick is to **borrow a
recognized-but-unused adapter key** (e.g. `typescript-language-server`) and
repurpose it to launch `markdown-lsp` for Markdown files. Put this in your
project (`.zed/settings.json`) or user settings:

```jsonc
{
  "languages": {
    "Markdown": {
      "language_servers": ["typescript-language-server"],
      "format_on_save": "on",
      "formatter": { "language_server": { "name": "typescript-language-server" } }
    }
  },
  "lsp": {
    "typescript-language-server": {
      "binary": {
        // Zed requires an ABSOLUTE path. Build first (cargo build --release or
        // nix build) and point at the result, or use the Nix-installed binary.
        "path": "/absolute/path/to/markdown-lsp",
        "arguments": []
      },
      // Passed through as the server's LSP `initializationOptions`.
      // Tip: run `markdown-lsp config` to get the full default block to paste here.
      "initialization_options": {
        "formatting": { "moveReferencesToBottom": true }
      }
    }
  }
}
```

Code actions ("Move link references to bottom", "Copy as inlined Markdown",
"Convert selection to inline links", …) appear in Zed's `editor: code actions`
menu. "Copy as inlined Markdown" needs a clipboard tool on `PATH`
(`wl-clipboard`, `xclip`, `xsel`, or `pbcopy`); the Nix package bundles them.

## Configuration

All settings are optional and have sensible defaults. Provide them through the
client's `initializationOptions` (or later via
`workspace/didChangeConfiguration`). A top-level `markdown-lsp` / `markdownLsp`
/ `markdown` wrapper key is accepted but not required.

Run `markdown-lsp config` to print a lightly commented, ready-to-edit JSONC
example with **every option at its current default** (always in sync with the
binary you have):

```bash
markdown-lsp config          # emit documented default settings as JSONC
```

```jsonc
{
  "folding": {
    "headings": true,
    "lists": true,
    "codeBlocks": true,
    "blockQuotes": true,
    "tables": true,
    "frontMatter": true
  },
  "completion": {
    "paths": true,
    // "relative" | "absolute" | "hybrid" | "auto".
    // Auto uses hybrid in a Git work tree and relative elsewhere.
    "pathStyle": "auto",
    // Extensions floated to the top of the completion list, highest first.
    "prioritizeExtensions": [".md", ".markdown"],
    // Offer hidden (dot) files/directories.
    "showHiddenFiles": false,
    // Respect .gitignore / .ignore / git excludes when walking the workspace
    // (so ignored files — node_modules, build output, … — aren't offered).
    "gitignore": true,
    // Search the whole workspace tree (fuzzy), not just the current directory.
    // When false, only the immediate directory is offered (no walking up/down).
    "deepPaths": true,
    // How deep the workspace walk recurses.
    "deepPathsMaxDepth": 8,
    // Upper bound on completion items returned (protects against huge trees).
    "maxItems": 256
  },
  "diagnostics": {
    "brokenLinks": true,
    // "error" | "warning" | "information" | "hint"
    "severity": "warning",
    "checkImages": true,
    // Glob patterns whose matching targets are never reported.
    "ignore": []
  },
  "formatting": {
    // When true, `textDocument/formatting` moves references to the bottom.
    // The code actions / commands below work regardless of this flag.
    "moveReferencesToBottom": true,
    "referencesHeading": "References",
    // When true, `textDocument/formatting` also normalises GFM tables.
    "formatTables": true,
    // When true, `textDocument/formatting` also normalises list markers
    // (bullets -> `-`, incremental ordered numbering, single-space gap).
    "formatLists": true
  },
  "snippets": {
    // Master switch for the `@`/`/` quick-command menu.
    "enabled": true,
    // Characters that open the menu at a word boundary (only the first char
    // of each entry is used).
    "triggers": ["/", "@"],
    // Offer workspace files as `[stem](path)` inline links.
    "fileLinks": true,
    // `chrono` strftime formats for the date/time snippets.
    "timeFormat": "%H:%M",
    "dateFormat": "%Y-%m-%d",
    "dateTimeFormat": "%Y-%m-%d %H:%M"
  },
  "journal": {
    // Directory (relative to the workspace root) holding the daily notes.
    "directory": "journal",
    // Template copied into a new note (relative to the workspace root). When
    // null or missing, a minimal note with a date heading is created instead.
    "template": null,
    // `chrono` strftime format for a note's file name.
    "filenameFormat": "%Y-%m-%d.md"
  },
  // Parse GitHub Flavored Markdown (tables, task lists, autolinks, ...).
  "gfm": true
}
```

### Project config file

Besides the client's `initializationOptions`, the server reads an optional
**`.markdown-lsp.json`** or **`.markdown-lsp.jsonc`** at the workspace root.
Both support JSONC comments and trailing commas. They use the exact same schema
as above (no wrapper key needed), and are **deep-merged over** the editor
settings key by key — so a project can pin, say, its journal template while each
developer keeps their personal preferences for everything else. If both files
exist, `.markdown-lsp.json` takes precedence.

```jsonc
// .markdown-lsp.jsonc  (committed to the repo)
{
  // Keep journals in one project-local directory.
  "journal": { "directory": "journal", "template": "journal/template.md" }
}
```

Precedence is *defaults → editor settings → project file* (project wins). The
file is re-read on `initialize`, on `didChangeConfiguration`, and whenever it
changes on disk. Keeping it in the repo makes project conventions **portable
across editors** — Zed, Neovim, VS Code, and the CLI all pick up the same
settings.

*How other tools do this:* Prettier (`.prettierrc`), ESLint (`.eslintrc`),
markdownlint (`.markdownlint.json`), rustfmt (`rustfmt.toml`) and EditorConfig
(`.editorconfig`) all use a discovered dotfile at (or above) the project root;
Ruff/Black read a `[tool.*]` table in `pyproject.toml`. We follow the same
convention with a single JSON file at the workspace root that mirrors the LSP
settings schema.

## Commands & code actions

These code actions and the equivalent `workspace/executeCommand` commands are
provided (all appear in the editor's code-action menu for any Markdown file):

| Command | Effect |
| --- | --- |
| `markdown-lsp.moveReferencesToBottom` | Rewrite inline links `[t](url)` to reference links `[t][id]` and gather the definitions under `# References` (edits the buffer). |
| `markdown-lsp.inlineReferences` | The inverse: expand reference links back to inline links and drop the definitions (edits the buffer). |
| `markdown-lsp.convertToInline` | Replace the **selection** (or whole document) *in place* with its inlined form. |
| `markdown-lsp.copyAsInlined` | Put the **selection** (or whole document), links expanded inline, on the **system clipboard** — *without* editing the buffer. |
| `markdown-lsp.openDailyNote` | Open the journal note for `today + <offset>` days, creating it from the template if it doesn't exist. Argument: an integer day offset (`0` today, `-1` yesterday, `1` tomorrow). |

`moveReferencesToBottom` / `inlineReferences` take the document URI as their only
argument. `convertToInline` and `copyAsInlined` take the URI plus an optional
selection `Range` as a second argument (an empty/absent range means the whole
document). `openDailyNote` takes the day offset.

### Daily / journal notes

`openDailyNote` is the equivalent of `cp journal/template.md journal/2026-07-07.md`
(when the target doesn't exist yet) followed by opening it — and just opens the
file when it already exists, never overwriting your notes. The path and template
come from the [`journal`](#configuration) config, and references are resolved
against the workspace root. Three code actions are offered — **Open today's /
yesterday's / tomorrow's journal note** — so they're one code-action menu away
in any Markdown file. From Neovim you can bind them directly:

```lua
-- Today / yesterday's note.
vim.keymap.set("n", "<leader>jt", function()
  vim.lsp.buf.execute_command({ command = "markdown-lsp.openDailyNote", arguments = { 0 } })
end)
vim.keymap.set("n", "<leader>jy", function()
  vim.lsp.buf.execute_command({ command = "markdown-lsp.openDailyNote", arguments = { -1 } })
end)
```

The server creates the note and asks the editor to open it via
`window/showDocument`, so it needs a client that supports that (Zed, Neovim, VS
Code all do).

### Inlining links: copy vs. convert

The idea: keep the *source* clean with reference links and definitions parked at
the bottom, but get plain inline links (no dangling `[id]`, no separate
definition block) when you lift a chunk out. Definitions are resolved across the
whole file, so a selection is self-contained even though its `[id]: url` lines
live elsewhere.

- **Convert** (`convertToInline`) edits the buffer, replacing the selection with
  its inlined version — a normal `applyEdit`, works in every LSP client.
- **Copy** (`copyAsInlined`) leaves the buffer untouched and writes the inlined
  text to the system clipboard directly (the server shells out to `wl-copy` /
  `xclip` / `xsel` / `pbcopy`), then reports the result via a `window/showMessage`
  notification. It also returns the text as the command result for programmatic
  clients. A clipboard tool must be on `PATH` (the Nix package bundles
  `wl-clipboard` + `xclip`).

**CLI alternative** — the `markdown-lsp inline` subcommand expands a whole
file/stdin and prints to stdout, so it composes with any clipboard tool:

```bash
markdown-lsp inline notes.md | wl-copy      # Wayland
markdown-lsp inline notes.md | pbcopy       # macOS
markdown-lsp inline notes.md | xclip -sel c # X11
```

(For a *partial* selection use the LSP command, which has the whole-file context
needed to resolve definitions that live outside the selection.)

## Command-line usage

The same binary doubles as a CLI. With no subcommand it speaks LSP over stdio
(as above); with `format` / `lint` it runs the formatter and broken-link checker
directly — handy for scripts, pre-commit hooks and CI.

`format`, `inline` and `lint` accept **files or directories** — a directory is
searched recursively for `*.md` / `*.markdown`, so `markdown-lsp format .`
handles a whole tree. The walk uses ripgrep's `ignore` crate, so it **respects
`.gitignore` / `.ignore`** and **skips hidden files** by default (which also
prunes `node_modules`, `target`, `.git`, …). Override with `--no-ignore` and
`--hidden`.

```bash
# Format: normalise tables and lists (and optionally consolidate references).
markdown-lsp format README.md            # print the formatted result to stdout
markdown-lsp format --write .            # rewrite every Markdown file under cwd
markdown-lsp format --check docs/        # exit non-zero if anything is unformatted
markdown-lsp format --move-references notes.md   # also move refs to the bottom
cat notes.md | markdown-lsp format --stdin       # read stdin, write stdout

# Inline: expand reference links to inline links (drop the definitions).
markdown-lsp inline notes.md | wl-copy           # copy a self-contained version
cat notes.md | markdown-lsp inline --stdin       # read stdin, write stdout

# Lint: report links/images pointing at files that do not exist.
markdown-lsp lint .                               # recurse the current directory
markdown-lsp lint --root . --no-images README.md

# Misc: print an example config (all defaults) or this README.
markdown-lsp config                               # default settings as JSON
markdown-lsp readme                               # print the README
```

`format` flags: `-w/--write`, `--check`, `-r/--move-references`, `--no-tables`,
`--no-lists`, `--references-heading <NAME>`, `--stdin`. `inline` flags:
`--references-heading <NAME>`, `--stdin`. `lint` flags: `--root <DIR>`,
`--no-images`. `format` / `inline` / `lint` also take `--no-ignore` (don't
respect `.gitignore`) and `--hidden` (include hidden files) for their directory
walk. `config` and `readme` take no arguments. All exit `0` when clean, `1` on
findings / changes, `2` on usage errors.

## How it works

```
LSP client ──stdio──► server.rs (tower-lsp-server Backend)   main.rs ──► cli.rs
                         │                                     (format / lint)
                         ├─ document.rs   Rope buffer + incremental edits
                         ├─ encoding.rs   Position ⇄ offset (UTF-8/UTF-16)
                         ├─ fuzzy.rs      nucleo-matcher path scoring
                         ├─ analysis.rs   parse (markdown-rs) → cached Analysis
                         │                  (headings, blocks, links, refs, defs)
                         └─ features/
                              folding · completion · snippets · diagnostics
                              formatting · tables · navigation · document_link
                              symbols · hover
```

- Parsing uses [`markdown`](https://docs.rs/markdown) (markdown-rs), whose mdast
  preserves the distinction between inline links, reference links and
  definitions and exposes byte-accurate offsets — ideal for both the formatter
  and precise diagnostic ranges.
- The reference-link formatter is a port of the accompanying TypeScript
  reference implementation, but works via minimal **position-based text edits**
  rather than re-serialising the whole document, so untouched text is preserved
  verbatim.
- `Analysis` is cached per document version; incremental `didChange` edits are
  applied to a `ropey` rope and diagnostics are debounced.

## Testing

```bash
cargo test         # or: nix develop --command cargo test
```

The suite includes per-feature unit tests (folding, completion incl. deep/fuzzy
paths, the `@`/`/` snippet menu with a fixed clock, diagnostics, tables,
navigation, hover, symbols, the fuzzy matcher), behavioural tests for the
formatter ported from the reference suite (plus inverse, round-trip and
range-inlining cases), temp-workspace tests for path completion and broken-link
diagnostics, position-encoding tests (multibyte/CRLF), CLI tests that drive the
built binary (`format`/`inline`/`lint`), and in-process JSON-RPC integration
tests (`initialize` → `didOpen` → `foldingRange`/`documentSymbol`/`definition`/
`references`/`documentLink`/`formatting`/`executeCommand`, including an
incremental edit and a regression test that `didChangeConfiguration` doesn't
clobber formatting settings).

### Benchmarks

Criterion benchmarks cover the hot paths (`cargo bench` or
`nix develop --command cargo bench`). Indicative numbers on a ~200-section
document:

| Benchmark | Time |
| --- | --- |
| `analyze` (full parse + summary) | ~20 ms |
| `to_reference_links` (parse + transform) | ~22 ms |
| `format_tables` (200-row table) | ~120 µs |
| `folding` (from cached analysis) | ~0.6 ms |
| `diagnostics` (from cached analysis) | ~15 µs |
| `fuzzy` (score 2000 nested paths) | ~0.9 ms |
| `completion` (workspace walk, ~1000 files, empty query) | ~2.8 ms |
| `completion` (workspace walk, ~1000 files, fuzzy query) | ~1.8 ms |
| `incremental_edit` (single change on a large rope) | ~1.3 µs |

The takeaway matches the design: a full parse is the only non-trivial cost, so
`Analysis` is cached per document version and diagnostics are debounced —
per-request features then run off the cache in the microsecond range, and
incremental `didChange` edits are ~1 µs.

## License

MIT OR Apache-2.0.
