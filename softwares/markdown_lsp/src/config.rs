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
    pub journal: JournalConfig,
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
            journal: JournalConfig::default(),
            gfm: true,
        }
    }
}

/// Top-level configuration keys we recognise (used to tell *our* settings apart
/// from unrelated payloads some clients send in `didChangeConfiguration`).
const KNOWN_KEYS: [&str; 7] = [
    "folding",
    "completion",
    "diagnostics",
    "formatting",
    "snippets",
    "journal",
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
        if !looks_like_ours(value) {
            return None;
        }
        Self::try_from_json_lenient(value)
    }

    /// Resolve the effective config from two optional layers, with the project
    /// file taking precedence over the client's settings (both over defaults):
    ///
    /// 1. `client` — the editor's `initializationOptions` /
    ///    `didChangeConfiguration` (per-user, per-editor).
    /// 2. `project` — a `.markdown-lsp.json` at the workspace root (per-project,
    ///    editor-agnostic).
    ///
    /// Objects are deep-merged key by key so a project can override just the
    /// keys it cares about (e.g. `journal.template`) and inherit the rest.
    pub fn resolve(
        client: Option<&serde_json::Value>,
        project: Option<&serde_json::Value>,
    ) -> Self {
        let client = client.map(unwrap_wrapper).unwrap_or(serde_json::Value::Null);
        let project = project.map(unwrap_wrapper).unwrap_or(serde_json::Value::Null);
        let merged = merge_values(client, project);
        serde_json::from_value(merged).unwrap_or_default()
    }

    /// Deserialize after stripping an optional wrapper key, without the
    /// "does this look like ours" gate.
    fn try_from_json_lenient(value: &serde_json::Value) -> Option<Self> {
        serde_json::from_value(unwrap_wrapper(value)).ok()
    }
}

/// Whether `value` carries our settings (a recognised wrapper key, or one of the
/// known top-level sections). Used to ignore unrelated `didChangeConfiguration`
/// payloads some clients send.
pub fn looks_like_ours(value: &serde_json::Value) -> bool {
    for key in ["markdown-lsp", "markdownLsp", "markdown"] {
        if value.get(key).is_some_and(|inner| !inner.is_null()) {
            return true;
        }
    }
    value
        .as_object()
        .is_some_and(|obj| KNOWN_KEYS.iter().any(|k| obj.contains_key(*k)))
}

/// Strip an optional `markdown-lsp` / `markdownLsp` / `markdown` wrapper key,
/// returning the inner object (or the value unchanged when unwrapped).
fn unwrap_wrapper(value: &serde_json::Value) -> serde_json::Value {
    for key in ["markdown-lsp", "markdownLsp", "markdown"] {
        if let Some(inner) = value.get(key) {
            if !inner.is_null() {
                return inner.clone();
            }
        }
    }
    value.clone()
}

/// Deep-merge two JSON values, with `over` winning: objects merge key by key,
/// while arrays and scalars from `over` replace `base`. A `null` in `over` is
/// treated as "unset" and leaves `base` intact.
fn merge_values(base: serde_json::Value, over: serde_json::Value) -> serde_json::Value {
    use serde_json::Value;
    match (base, over) {
        (Value::Object(mut b), Value::Object(o)) => {
            for (k, v) in o {
                let merged = match b.remove(&k) {
                    Some(existing) => merge_values(existing, v),
                    None => v,
                };
                b.insert(k, merged);
            }
            Value::Object(b)
        }
        (base, Value::Null) => base,
        (_, over) => over,
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
    /// Respect `.gitignore` / `.ignore` / git excludes (and global gitignore)
    /// when walking the workspace, so ignored files aren't offered.
    pub gitignore: bool,
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
            gitignore: true,
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
    /// When `true`, `textDocument/formatting` normalises list markers: bullets
    /// become `-`, ordered lists are renumbered incrementally, and the gap
    /// after a marker collapses to a single space.
    pub format_lists: bool,
}

impl Default for FormattingConfig {
    fn default() -> Self {
        Self {
            move_references_to_bottom: true,
            references_heading: "References".to_string(),
            format_tables: true,
            format_lists: true,
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

/// Daily-note ("journal") commands.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(default, rename_all = "camelCase")]
pub struct JournalConfig {
    /// Directory (relative to the workspace root, unless absolute) that holds
    /// the daily notes.
    pub directory: String,
    /// Optional template copied into a new note. Relative paths resolve against
    /// the workspace root. When unset (or missing on disk), a minimal note with
    /// a date heading is created instead.
    pub template: Option<String>,
    /// [`chrono`] format string for a note's file name.
    pub filename_format: String,
}

impl Default for JournalConfig {
    fn default() -> Self {
        Self {
            directory: "journal".to_string(),
            template: Some("journal/template.md".to_string()),
            filename_format: "%Y-%m-%d.md".to_string(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn project_file_overrides_client_but_keeps_other_keys() {
        let client = json!({
            "formatting": { "moveReferencesToBottom": false, "referencesHeading": "Links" },
            "gfm": true
        });
        let project = json!({
            "journal": { "template": "journal/template.md" },
            "formatting": { "moveReferencesToBottom": true }
        });
        let cfg = Config::resolve(Some(&client), Some(&project));

        // Project wins on the key it sets...
        assert!(cfg.formatting.move_references_to_bottom);
        // ...but the client's sibling key is preserved (deep merge, not replace).
        assert_eq!(cfg.formatting.references_heading, "Links");
        // ...and project-only keys apply.
        assert_eq!(cfg.journal.template.as_deref(), Some("journal/template.md"));
    }

    #[test]
    fn resolve_tolerates_missing_layers_and_wrappers() {
        assert!(!Config::resolve(None, None).journal.directory.is_empty());
        let wrapped = json!({ "markdown-lsp": { "gfm": false } });
        let cfg = Config::resolve(Some(&wrapped), None);
        assert!(!cfg.gfm);
    }
}
