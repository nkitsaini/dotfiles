//! User-facing configuration.
//!
//! The whole tree deserializes from the client's `initializationOptions` (and
//! later `workspace/didChangeConfiguration`). Every field has a sensible
//! default so a client can send `{}` — or nothing at all — and still get useful
//! behaviour. Field names use `camelCase` to match typical LSP settings.

use serde::{Deserialize, Serialize};

/// Root configuration object.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct Config {
    pub folding: FoldingConfig,
    pub completion: CompletionConfig,
    pub diagnostics: DiagnosticsConfig,
    pub formatting: FormattingConfig,
    pub snippets: SnippetsConfig,
    /// Parse GitHub Flavored Markdown (tables, task lists, autolinks, ...).
    pub gfm: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            folding: FoldingConfig::default(),
            completion: CompletionConfig::default(),
            diagnostics: DiagnosticsConfig::default(),
            formatting: FormattingConfig::default(),
            snippets: SnippetsConfig::default(),
            gfm: true,
        }
    }
}

/// Top-level configuration keys we recognise (used to tell *our* settings apart
/// from unrelated payloads some clients send in `didChangeConfiguration`).
const KNOWN_KEYS: [&str; 6] = [
    "folding",
    "completion",
    "diagnostics",
    "formatting",
    "snippets",
    "gfm",
];

impl Config {
    /// Deserialize from an arbitrary JSON value, tolerating a top-level wrapper
    /// key (`markdown-lsp` / `markdownLsp` / `markdown`) that some clients add.
    /// Unknown/empty payloads fall back to defaults.
    pub fn from_json(value: serde_json::Value) -> Self {
        Self::try_from_json(&value).unwrap_or_default()
    }

    /// Like [`Self::from_json`] but returns `None` when `value` doesn't look
    /// like our configuration at all (e.g. `null`, `{}`, or another server's
    /// settings). This lets `workspace/didChangeConfiguration` avoid clobbering
    /// a good `initializationOptions` config with an unrelated payload — the
    /// bug that stopped `textDocument/formatting` from moving references.
    pub fn try_from_json(value: &serde_json::Value) -> Option<Self> {
        for key in ["markdown-lsp", "markdownLsp", "markdown"] {
            if let Some(inner) = value.get(key) {
                if !inner.is_null() {
                    return serde_json::from_value(inner.clone()).ok();
                }
            }
        }
        let obj = value.as_object()?;
        if KNOWN_KEYS.iter().any(|k| obj.contains_key(*k)) {
            serde_json::from_value(value.clone()).ok()
        } else {
            None
        }
    }
}

/// Which structural elements produce folding ranges.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FoldingConfig {
    pub headings: bool,
    pub lists: bool,
    pub code_blocks: bool,
    pub block_quotes: bool,
    pub tables: bool,
    pub front_matter: bool,
}

impl Default for FoldingConfig {
    fn default() -> Self {
        Self {
            headings: true,
            lists: true,
            code_blocks: true,
            block_quotes: true,
            tables: true,
            front_matter: true,
        }
    }
}

/// Path-completion behaviour.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct CompletionConfig {
    /// Master switch for link/image path completion.
    pub paths: bool,
    /// Extensions that are sorted to the top of the list (highest priority
    /// first).
    pub prioritize_extensions: Vec<String>,
    /// Offer dotfiles / hidden directories.
    pub show_hidden_files: bool,
    /// Also offer files in nested directories, fuzzy-matched (fzf style), not
    /// just entries of the immediate directory.
    pub deep_paths: bool,
    /// How deep to recurse for [`Self::deep_paths`] (relative to the directory
    /// being completed).
    pub deep_paths_max_depth: usize,
    /// Upper bound on total completion items returned (protects against huge
    /// trees).
    pub max_items: usize,
}

impl Default for CompletionConfig {
    fn default() -> Self {
        Self {
            paths: true,
            prioritize_extensions: vec![".md".to_string(), ".markdown".to_string()],
            show_hidden_files: false,
            deep_paths: true,
            deep_paths_max_depth: 8,
            max_items: 256,
        }
    }
}

/// Broken-link diagnostics.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct DiagnosticsConfig {
    /// Warn about links/images that point at local files which do not exist.
    pub broken_links: bool,
    /// Severity used for the "file does not exist" diagnostic.
    pub severity: Severity,
    /// Also validate image (`![]()`) destinations.
    pub check_images: bool,
    /// Glob patterns whose matching targets are never reported.
    pub ignore: Vec<String>,
}

impl Default for DiagnosticsConfig {
    fn default() -> Self {
        Self {
            broken_links: true,
            severity: Severity::Warning,
            check_images: true,
            ignore: Vec::new(),
        }
    }
}

/// Diagnostic severity, mirroring the LSP levels.
#[derive(Debug, Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Error,
    Warning,
    Information,
    Hint,
}

/// Formatter behaviour.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct FormattingConfig {
    /// When `true`, `textDocument/formatting` rewrites inline links to
    /// reference links and consolidates the definitions at the bottom of the
    /// file. When `false`, this part of formatting is skipped (the on-demand
    /// code actions and commands still work regardless of this flag).
    pub move_references_to_bottom: bool,
    /// Heading text used for the generated references section.
    pub references_heading: String,
    /// When `true`, `textDocument/formatting` normalises GFM tables (aligns
    /// columns, adds missing pipes / separator rows, etc.).
    pub format_tables: bool,
}

impl Default for FormattingConfig {
    fn default() -> Self {
        Self {
            move_references_to_bottom: true,
            references_heading: "References".to_string(),
            format_tables: true,
        }
    }
}

/// Quick-insert "slash / at" command completions (dates, times, file links).
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct SnippetsConfig {
    /// Master switch for the `@`/`/` quick-command menu.
    pub enabled: bool,
    /// Characters that open the menu at a word boundary (start of line or after
    /// whitespace). Only the first `char` of each entry is used.
    pub triggers: Vec<String>,
    /// Offer workspace files, inserting each as an inline link
    /// `[stem](path)` (path style matches path completion: relative for
    /// files at/below the document, absolute for files above it).
    pub file_links: bool,
    /// [`chrono`] format string for the `now` (time) snippet.
    pub time_format: String,
    /// [`chrono`] format string for the `today` / `tomorrow` / `yesterday`
    /// (date) snippets.
    pub date_format: String,
    /// [`chrono`] format string for the `datetime` snippet.
    pub date_time_format: String,
}

impl Default for SnippetsConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            triggers: vec!["/".to_string(), "@".to_string()],
            file_links: true,
            time_format: "%H:%M".to_string(),
            date_format: "%Y-%m-%d".to_string(),
            date_time_format: "%Y-%m-%d %H:%M".to_string(),
        }
    }
}
