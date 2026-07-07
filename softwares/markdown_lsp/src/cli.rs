//! Command-line interface: run the formatter and the broken-link linter without
//! an editor.
//!
//! ```text
//! markdown-lsp format [--write|--check] [--move-references] [--no-tables] [FILES...]
//! markdown-lsp inline [--references-heading NAME] [--stdin] [FILES...]
//! markdown-lsp lint   [--root DIR] [--no-images] FILES...
//! ```
//!
//! With no subcommand the binary speaks LSP over stdio (see `main.rs`).

use std::path::{Path, PathBuf};

use ropey::Rope;

use crate::analysis::analyze;
use crate::config::{DiagnosticsConfig, FormattingConfig};
use crate::encoding::PositionEncoding;
use crate::features::{diagnostics, formatting};

/// Dispatch a CLI subcommand. `args[0]` is the subcommand name. Returns a
/// process exit code.
pub fn run(args: &[String]) -> i32 {
    match args.first().map(String::as_str) {
        Some("format") => cmd_format(&args[1..]),
        Some("inline") => cmd_inline(&args[1..]),
        Some("lint") | Some("check") => cmd_lint(&args[1..]),
        Some("config") => cmd_config(),
        Some("readme") => cmd_readme(),
        _ => {
            print_help();
            2
        }
    }
}

/// Print an example configuration (every option at its default value) as JSON.
/// Handy for seeding an editor's settings — see the README for where it goes.
fn cmd_config() -> i32 {
    match serde_json::to_string_pretty(&crate::config::Config::default()) {
        Ok(json) => {
            println!("{json}");
            0
        }
        Err(e) => {
            eprintln!("failed to serialize config: {e}");
            1
        }
    }
}

/// Print this crate's README (embedded at build time).
fn cmd_readme() -> i32 {
    print!("{}", include_str!("../README.md"));
    0
}

/// Top-level `--help` text.
pub fn print_help() {
    eprintln!(
        "markdown-lsp {}\n\
\n\
USAGE:\n\
    markdown-lsp                       Run the language server over stdio (default)\n\
    markdown-lsp format [OPTIONS] [FILES...]\n\
    markdown-lsp inline [OPTIONS] [FILES...]\n\
    markdown-lsp lint   [OPTIONS] FILES...\n\
    markdown-lsp config                Print an example config (all defaults) as JSON\n\
    markdown-lsp readme                Print the README to stdout\n\
\n\
FORMAT OPTIONS:\n\
    -w, --write             Rewrite files in place (default: print to stdout)\n\
        --check             Exit non-zero if any file is not already formatted\n\
    -r, --move-references   Consolidate reference links under a heading at the bottom\n\
        --no-tables         Do not reformat GFM tables\n\
        --references-heading <NAME>   Heading for the references section (default: References)\n\
        --stdin             Read from stdin, write to stdout\n\
\n\
INLINE OPTIONS (expand reference links to inline, dropping the definitions —\n\
handy for copying self-contained Markdown, e.g. `markdown-lsp inline notes.md | wl-copy`):\n\
        --references-heading <NAME>   Heading of the references section to drop (default: References)\n\
        --stdin             Read from stdin, write to stdout\n\
\n\
LINT OPTIONS:\n\
        --root <DIR>        Workspace root for absolute-path links (default: cwd)\n\
        --no-images         Skip image (`![]()`) destinations\n\
\n\
OTHER:\n\
    -h, --help              Show this help\n\
    -V, --version           Show version",
        env!("CARGO_PKG_VERSION")
    );
}

// ---------------------------------------------------------------------------
// format
// ---------------------------------------------------------------------------

fn cmd_format(args: &[String]) -> i32 {
    let mut write = false;
    let mut check = false;
    let mut use_stdin = false;
    let mut cfg = FormattingConfig {
        move_references_to_bottom: false,
        format_tables: true,
        ..FormattingConfig::default()
    };
    let mut files: Vec<String> = Vec::new();

    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "-w" | "--write" => write = true,
            "--check" => check = true,
            "--stdin" => use_stdin = true,
            "-r" | "--move-references" => cfg.move_references_to_bottom = true,
            "--no-tables" => cfg.format_tables = false,
            "--references-heading" => match it.next() {
                Some(v) => cfg.references_heading = v.clone(),
                None => {
                    eprintln!("--references-heading requires a value");
                    return 2;
                }
            },
            "-h" | "--help" => {
                print_help();
                return 0;
            }
            other if other.starts_with('-') && other != "-" => {
                eprintln!("format: unknown option '{other}'");
                return 2;
            }
            other => files.push(other.to_string()),
        }
    }

    if use_stdin || files.is_empty() {
        let source = read_stdin();
        print!("{}", formatting::format_document(&source, true, &cfg));
        return 0;
    }

    let mut changed = false;
    let mut had_error = false;
    for file in &files {
        let source = match std::fs::read_to_string(file) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("{file}: {e}");
                had_error = true;
                continue;
            }
        };
        let formatted = formatting::format_document(&source, true, &cfg);
        let file_changed = formatted != source;
        changed |= file_changed;

        if check {
            if file_changed {
                println!("would reformat {file}");
            }
        } else if write {
            if file_changed {
                if let Err(e) = std::fs::write(file, &formatted) {
                    eprintln!("{file}: {e}");
                    had_error = true;
                } else {
                    println!("formatted {file}");
                }
            }
        } else {
            print!("{formatted}");
        }
    }

    if had_error || (check && changed) {
        1
    } else {
        0
    }
}

// ---------------------------------------------------------------------------
// inline
// ---------------------------------------------------------------------------

/// Expand reference links to inline links (dropping the definitions and the
/// references heading) and print the result to stdout. Non-destructive by
/// design: it never rewrites files, so it composes with a clipboard tool, e.g.
/// `markdown-lsp inline notes.md | pbcopy`.
fn cmd_inline(args: &[String]) -> i32 {
    let mut use_stdin = false;
    let mut references_heading = "References".to_string();
    let mut files: Vec<String> = Vec::new();

    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--stdin" => use_stdin = true,
            "--references-heading" => match it.next() {
                Some(v) => references_heading = v.clone(),
                None => {
                    eprintln!("--references-heading requires a value");
                    return 2;
                }
            },
            "-h" | "--help" => {
                print_help();
                return 0;
            }
            other if other.starts_with('-') && other != "-" => {
                eprintln!("inline: unknown option '{other}'");
                return 2;
            }
            other => files.push(other.to_string()),
        }
    }

    if use_stdin || files.is_empty() {
        let source = read_stdin();
        print!("{}", formatting::to_inline_links(&source, true, &references_heading));
        return 0;
    }

    let mut had_error = false;
    for file in &files {
        let source = match std::fs::read_to_string(file) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("{file}: {e}");
                had_error = true;
                continue;
            }
        };
        print!("{}", formatting::to_inline_links(&source, true, &references_heading));
    }

    if had_error {
        1
    } else {
        0
    }
}

// ---------------------------------------------------------------------------
// lint
// ---------------------------------------------------------------------------

/// A single lint finding, in editor-friendly 1-based coordinates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LintIssue {
    pub line: usize,
    pub column: usize,
    pub message: String,
}

fn cmd_lint(args: &[String]) -> i32 {
    let mut root: Option<PathBuf> = None;
    let mut check_images = true;
    let mut files: Vec<String> = Vec::new();

    let mut it = args.iter();
    while let Some(arg) = it.next() {
        match arg.as_str() {
            "--root" => match it.next() {
                Some(v) => root = Some(PathBuf::from(v)),
                None => {
                    eprintln!("--root requires a value");
                    return 2;
                }
            },
            "--no-images" => check_images = false,
            "-h" | "--help" => {
                print_help();
                return 0;
            }
            other if other.starts_with('-') && other != "-" => {
                eprintln!("lint: unknown option '{other}'");
                return 2;
            }
            other => files.push(other.to_string()),
        }
    }

    if files.is_empty() {
        eprintln!("lint: no files given");
        return 2;
    }

    let root = root
        .or_else(|| std::env::current_dir().ok())
        .map(|p| crate::uri::normalize(&p));
    let cfg = DiagnosticsConfig {
        broken_links: true,
        check_images,
        ..DiagnosticsConfig::default()
    };

    let mut total = 0usize;
    let mut had_error = false;
    for file in &files {
        let source = match std::fs::read_to_string(file) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("{file}: {e}");
                had_error = true;
                continue;
            }
        };
        let doc_path = absolutize(Path::new(file));
        let issues = lint_source(&source, Some(&doc_path), root.as_deref(), &cfg);
        for issue in &issues {
            println!("{file}:{}:{}: {}", issue.line, issue.column, issue.message);
            total += 1;
        }
    }

    if had_error || total > 0 {
        1
    } else {
        0
    }
}

/// Pure linting helper: broken-link findings for `text`. Byte columns are
/// reported (1-based).
pub fn lint_source(
    text: &str,
    doc_path: Option<&Path>,
    workspace_root: Option<&Path>,
    cfg: &DiagnosticsConfig,
) -> Vec<LintIssue> {
    let analysis = analyze(text, 0);
    let rope = Rope::from_str(text);
    // UTF-8 encoding => `character` is a byte offset within the line.
    let diags = diagnostics::diagnostics(
        &analysis,
        &rope,
        cfg,
        PositionEncoding::Utf8,
        doc_path,
        workspace_root,
    );
    diags
        .into_iter()
        .map(|d| LintIssue {
            line: d.range.start.line as usize + 1,
            column: d.range.start.character as usize + 1,
            message: d.message,
        })
        .collect()
}

fn absolutize(path: &Path) -> PathBuf {
    let joined = if path.is_absolute() {
        path.to_path_buf()
    } else {
        std::env::current_dir()
            .map(|cwd| cwd.join(path))
            .unwrap_or_else(|_| path.to_path_buf())
    };
    crate::uri::normalize(&joined)
}

fn read_stdin() -> String {
    use std::io::Read;
    let mut buf = String::new();
    let _ = std::io::stdin().read_to_string(&mut buf);
    buf
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::tempdir;

    #[test]
    fn lint_reports_missing_file() {
        let dir = tempdir().unwrap();
        fs::write(dir.path().join("exists.md"), "").unwrap();
        let doc = dir.path().join("index.md");
        let text = "[a](./exists.md)\n\n[b](./missing.md)\n";
        let issues = lint_source(
            text,
            Some(&doc),
            Some(dir.path()),
            &DiagnosticsConfig::default(),
        );
        assert_eq!(issues.len(), 1);
        assert_eq!(issues[0].line, 3);
        assert!(issues[0].message.contains("missing.md"));
    }

    #[test]
    fn format_via_cli_helper_moves_references() {
        let cfg = FormattingConfig {
            move_references_to_bottom: true,
            format_tables: true,
            ..FormattingConfig::default()
        };
        let out = formatting::format_document("[x](https://a.com)\n", true, &cfg);
        assert!(out.contains("[x][1]"));
        assert!(out.contains("[1]: https://a.com"));
    }

    #[test]
    fn format_via_cli_helper_formats_tables() {
        let cfg = FormattingConfig::default();
        let out = formatting::format_document("a | b | c\n", true, &cfg);
        assert!(out.contains("| a"));
        assert!(out.contains("| ---"));
    }
}
