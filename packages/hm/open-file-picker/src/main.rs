use std::collections::{HashMap, HashSet};
use std::env;
use std::ffi::{OsStr, OsString};
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::os::unix::ffi::OsStringExt;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{mpsc, Arc};
use std::thread;
use std::time::{Duration, Instant};

use crossterm::cursor::{Hide, Show};
use crossterm::event::{
    self, DisableBracketedPaste, EnableBracketedPaste, Event, KeyCode, KeyEvent, KeyEventKind,
    KeyModifiers,
};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use nucleo::pattern::{CaseMatching, Normalization};
use nucleo::{Config, Nucleo, Snapshot};
use ratatui::backend::CrosstermBackend;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Color, Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, BorderType, Borders, List, ListItem, ListState, Paragraph};
use ratatui::{Frame, Terminal};
use unicode_width::{UnicodeWidthChar, UnicodeWidthStr};

const SEARCH: &str = "@SEARCH@";
const GIO: &str = "@GIO@";
const SETSID: &str = "@SETSID@";
const FRAME_INTERVAL: Duration = Duration::from_millis(16);
const HIDDEN_FALLBACK_THRESHOLD: u32 = 20;
const HISTORY_LIMIT: usize = 256;

#[derive(Clone, Debug, Eq, PartialEq)]
enum Scope {
    Home,
    Exact(PathBuf),
    Filesystem,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum CandidateKind {
    Normal,
    Fallback,
}

#[derive(Debug)]
struct CandidateResult {
    generation: u64,
    kind: CandidateKind,
    paths: io::Result<Vec<PathBuf>>,
}

struct App {
    home: PathBuf,
    query: String,
    query_cursor: usize,
    scope: Scope,
    generation: u64,
    generation_token: Arc<std::sync::atomic::AtomicU64>,
    history_rank: HashMap<PathBuf, usize>,
    candidate_kind: CandidateKind,
    loading: bool,
    refreshing: bool,
    fallback_query: Option<String>,
    selected: u32,
    matcher_stable: bool,
    display_paths: Vec<PathBuf>,
    display_matched: u32,
    display_total: u32,
    display_selected_row: usize,
    recent_prefix: Vec<PathBuf>,
    recent_set: HashSet<PathBuf>,
    recent_prefix_dirty: bool,
    accept_when_stable: bool,
    nucleo: Nucleo<PathBuf>,
    result_tx: mpsc::Sender<CandidateResult>,
    result_rx: mpsc::Receiver<CandidateResult>,
    redraw_requested: Arc<AtomicBool>,
    message: Option<String>,
}

impl App {
    fn new(home: PathBuf) -> Self {
        let redraw_requested = Arc::new(AtomicBool::new(true));
        let config = Config::DEFAULT.match_paths();
        // The event loop ticks Nucleo every 16 ms. Its notifier is deliberately
        // a no-op: one notification is emitted per injected path in Nucleo 0.5,
        // and treating those as redraw requests would bring the flicker back.
        let nucleo = Nucleo::new(config, Arc::new(|| {}), None, 1);
        let (result_tx, result_rx) = mpsc::channel();
        let generation_token = Arc::new(std::sync::atomic::AtomicU64::new(0));
        let history_rank = load_history()
            .into_iter()
            .enumerate()
            .map(|(rank, path)| (path, rank))
            .collect();
        let mut app = Self {
            home,
            query: String::new(),
            query_cursor: 0,
            scope: Scope::Home,
            generation: 0,
            generation_token,
            history_rank,
            candidate_kind: CandidateKind::Normal,
            loading: false,
            refreshing: false,
            fallback_query: None,
            selected: 0,
            matcher_stable: false,
            display_paths: Vec::new(),
            display_matched: 0,
            display_total: 0,
            display_selected_row: 0,
            recent_prefix: Vec::new(),
            recent_set: HashSet::new(),
            recent_prefix_dirty: true,
            accept_when_stable: false,
            nucleo,
            result_tx,
            result_rx,
            redraw_requested,
            message: None,
        };
        app.reload_candidates(CandidateKind::Normal);
        app
    }

    fn reload_candidates(&mut self, kind: CandidateKind) {
        self.generation += 1;
        self.generation_token
            .store(self.generation, Ordering::Release);
        let generation = self.generation;
        let query = self.query.clone();
        let scope = self.scope.clone();
        let history_rank = self.history_rank.clone();
        let tx = self.result_tx.clone();
        self.loading = true;
        self.refreshing = false;
        self.matcher_stable = false;
        self.candidate_kind = kind;
        self.redraw_requested.store(true, Ordering::Release);

        thread::spawn(move || {
            let paths = match (&scope, kind) {
                (Scope::Home, CandidateKind::Normal) => load_home_candidates(),
                (_, CandidateKind::Normal) => run_search("normal", &query),
                (_, CandidateKind::Fallback) => run_search("fallback", &query),
            }
            .map(|paths| prioritize_paths(paths, &history_rank));
            let _ = tx.send(CandidateResult {
                generation,
                kind,
                paths,
            });
        });
    }

    fn refresh_index(&mut self) {
        if self.refreshing {
            return;
        }
        self.refreshing = true;
        self.message = None;
        self.redraw_requested.store(true, Ordering::Release);
        let tx = self.result_tx.clone();
        let query = self.query.clone();
        let scope = self.scope.clone();
        let history_rank = self.history_rank.clone();
        let generation = self.generation + 1;
        self.generation = generation;
        self.generation_token.store(generation, Ordering::Release);
        thread::spawn(move || {
            let status = Command::new(SEARCH)
                .arg("refresh")
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status();
            let paths = match status {
                Ok(status) if status.success() => match scope {
                    Scope::Home => load_home_candidates(),
                    Scope::Exact(_) | Scope::Filesystem => run_search("normal", &query),
                },
                Ok(status) => Err(io::Error::other(format!(
                    "index refresh exited with {status}"
                ))),
                Err(error) => Err(error),
            }
            .map(|paths| prioritize_paths(paths, &history_rank));
            let _ = tx.send(CandidateResult {
                generation,
                kind: CandidateKind::Normal,
                paths,
            });
        });
    }

    fn receive_candidates(&mut self) {
        while let Ok(result) = self.result_rx.try_recv() {
            if result.generation != self.generation {
                continue;
            }
            self.loading = false;
            self.refreshing = false;
            match result.paths {
                Ok(paths) => {
                    let count = paths.len();
                    // Keep the old snapshot on-screen until Nucleo publishes the
                    // replacement. This is the main difference from fzf reloads.
                    self.nucleo.restart(false);
                    self.matcher_stable = false;
                    self.recent_prefix_dirty = true;
                    self.recent_prefix.clear();
                    self.recent_set.clear();
                    let injector = self.nucleo.injector();
                    let generation_token = self.generation_token.clone();
                    let generation = result.generation;
                    // Nucleo 0.5 injectors are thread-safe. Populate the new
                    // generation away from the UI thread so even a very large
                    // home index cannot pause input or rendering.
                    thread::spawn(move || {
                        for path in paths {
                            if generation_token.load(Ordering::Acquire) != generation {
                                break;
                            }
                            injector.push(path, |path, columns| {
                                columns[0] = path.to_string_lossy().into();
                            });
                        }
                    });
                    self.candidate_kind = result.kind;
                    self.message = if count == 0 {
                        Some("No candidates in this scope".to_owned())
                    } else {
                        None
                    };
                    self.reparse_pattern(false);
                }
                Err(error) => {
                    self.message = Some(format!("Search failed: {error}"));
                }
            }
            self.redraw_requested.store(true, Ordering::Release);
        }
    }

    fn reparse_pattern(&mut self, appended: bool) {
        let pattern = match_query(&self.query, &self.scope);
        self.nucleo.pattern.reparse(
            0,
            pattern,
            CaseMatching::Smart,
            Normalization::Smart,
            appended,
        );
        self.selected = 0;
        self.matcher_stable = false;
        self.recent_prefix_dirty = true;
        self.recent_prefix.clear();
        self.recent_set.clear();
        self.redraw_requested.store(true, Ordering::Release);
    }

    fn rebuild_recent_prefix(&mut self) {
        if !self.recent_prefix_dirty {
            return;
        }
        self.recent_prefix_dirty = false;
        self.recent_prefix.clear();
        self.recent_set.clear();
        if !self.query.is_empty() || self.history_rank.is_empty() {
            return;
        }

        let mut recent = self
            .nucleo
            .snapshot()
            .matched_items(..)
            .filter_map(|item| {
                self.history_rank
                    .get(item.data)
                    .copied()
                    .map(|rank| (rank, item.data.clone()))
            })
            .collect::<Vec<_>>();
        recent.sort_unstable_by_key(|(rank, _)| *rank);
        self.recent_prefix = recent
            .into_iter()
            .map(|(_, path)| path)
            .take(HISTORY_LIMIT)
            .collect();
        self.recent_set.extend(self.recent_prefix.iter().cloned());
    }

    fn query_changed(&mut self, old_query: &str) {
        self.message = None;
        self.accept_when_stable = false;
        self.fallback_query = None;
        let old_explicit_hidden = requests_hidden(old_query, &self.scope);
        let new_scope = classify_scope(&self.query, &self.home);
        let new_explicit_hidden = requests_hidden(&self.query, &new_scope);
        let scope_changed = new_scope != self.scope;
        let was_append = self.query.starts_with(old_query);
        self.scope = new_scope;

        if scope_changed
            || old_explicit_hidden != new_explicit_hidden
            || self.candidate_kind == CandidateKind::Fallback
        {
            self.reload_candidates(CandidateKind::Normal);
        }
        self.reparse_pattern(was_append && !scope_changed);
    }

    fn maybe_start_fallback(&mut self, matcher_running: bool) {
        if self.query.is_empty()
            || self.loading
            || matcher_running
            || self.nucleo.active_injectors() != 0
            || !sparse_results_need_hidden_fallback(self.nucleo.snapshot().matched_item_count())
            || self.fallback_query.as_deref() == Some(&self.query)
        {
            return;
        }
        self.fallback_query = Some(self.query.clone());
        self.reload_candidates(CandidateKind::Fallback);
    }

    fn insert(&mut self, text: &str) {
        let old = self.query.clone();
        self.query.insert_str(self.query_cursor, text);
        self.query_cursor += text.len();
        self.query_changed(&old);
    }

    fn backspace(&mut self) {
        if self.query_cursor == 0 {
            return;
        }
        let old = self.query.clone();
        let previous = previous_boundary(&self.query, self.query_cursor);
        self.query.drain(previous..self.query_cursor);
        self.query_cursor = previous;
        self.query_changed(&old);
    }

    fn delete(&mut self) {
        if self.query_cursor == self.query.len() {
            return;
        }
        let old = self.query.clone();
        let next = next_boundary(&self.query, self.query_cursor);
        self.query.drain(self.query_cursor..next);
        self.query_changed(&old);
    }

    fn delete_word(&mut self) {
        if self.query_cursor == 0 {
            return;
        }
        let old = self.query.clone();
        let before = &self.query[..self.query_cursor];
        let trimmed = before.trim_end_matches(|character: char| character.is_whitespace());
        let start = trimmed
            .char_indices()
            .rev()
            .find(|(_, character)| character.is_whitespace() || *character == '/')
            .map_or(0, |(index, character)| index + character.len_utf8());
        self.query.drain(start..self.query_cursor);
        self.query_cursor = start;
        self.query_changed(&old);
    }

    fn move_selection(&mut self, amount: u32, down: bool) {
        if !self.matcher_stable {
            return;
        }
        let count = self.nucleo.snapshot().matched_item_count();
        if count == 0 {
            self.selected = 0;
        } else if down {
            self.selected = (self.selected + amount).min(count - 1);
        } else {
            self.selected = self.selected.saturating_sub(amount);
        }
        self.redraw_requested.store(true, Ordering::Release);
    }

    fn selection(&self) -> Option<PathBuf> {
        if !self.matcher_stable {
            return None;
        }
        if self.query.is_empty() && !self.recent_prefix.is_empty() {
            return recent_match_at(
                self.nucleo.snapshot(),
                self.selected,
                &self.recent_prefix,
                &self.recent_set,
            );
        }
        self.nucleo
            .snapshot()
            .get_matched_item(self.selected)
            .map(|item| item.data.clone())
    }

    fn complete_selection(&mut self) {
        let Some(path) = self.selection() else {
            return;
        };
        let mut completed = display_query_path(&path, &self.home);
        if path.is_dir() && !completed.ends_with('/') {
            completed.push('/');
        }
        let old = std::mem::replace(&mut self.query, completed);
        self.query_cursor = self.query.len();
        self.query_changed(&old);
    }
}

fn recent_match_at(
    snapshot: &Snapshot<PathBuf>,
    index: u32,
    recent_prefix: &[PathBuf],
    recent_set: &HashSet<PathBuf>,
) -> Option<PathBuf> {
    if let Some(path) = recent_prefix.get(index as usize) {
        return Some(path.clone());
    }
    let non_recent_index = index.checked_sub(recent_prefix.len() as u32)?;
    snapshot
        .matched_items(..)
        .filter(|item| !recent_set.contains(item.data))
        .nth(non_recent_index as usize)
        .map(|item| item.data.clone())
}

fn recent_match_page(
    snapshot: &Snapshot<PathBuf>,
    offset: u32,
    end: u32,
    recent_prefix: &[PathBuf],
    recent_set: &HashSet<PathBuf>,
) -> Vec<PathBuf> {
    let recent_count = recent_prefix.len() as u32;
    let mut non_recent = snapshot
        .matched_items(..)
        .filter(|item| !recent_set.contains(item.data));
    if offset > recent_count {
        let _ = non_recent.nth((offset - recent_count - 1) as usize);
    }

    (offset..end)
        .filter_map(|index| {
            if index < recent_count {
                recent_prefix.get(index as usize).cloned()
            } else {
                non_recent.next().map(|item| item.data.clone())
            }
        })
        .collect()
}

fn prioritize_paths(paths: Vec<PathBuf>, history_rank: &HashMap<PathBuf, usize>) -> Vec<PathBuf> {
    if history_rank.is_empty() {
        return paths;
    }
    let mut recent = Vec::new();
    let mut remaining = Vec::with_capacity(paths.len());
    for path in paths {
        if let Some(&rank) = history_rank.get(&path) {
            recent.push((rank, path));
        } else {
            remaining.push(path);
        }
    }
    recent.sort_unstable_by_key(|(rank, _)| *rank);
    recent
        .into_iter()
        .map(|(_, path)| path)
        .chain(remaining)
        .collect()
}

fn home_directory() -> PathBuf {
    env::var_os("HOME").map_or_else(|| PathBuf::from("/"), PathBuf::from)
}

fn cache_directory() -> PathBuf {
    env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_directory().join(".cache"))
        .join("open-file-picker")
}

fn history_path() -> PathBuf {
    cache_directory().join("history.nul")
}

fn load_history() -> Vec<PathBuf> {
    let Ok(data) = fs::read(history_path()) else {
        return Vec::new();
    };
    parse_nul_paths(data)
        .into_iter()
        .take(HISTORY_LIMIT)
        .collect()
}

fn record_history(target: &OsStr) -> io::Result<()> {
    let target = PathBuf::from(target);
    let target = if target.is_absolute() {
        target
    } else {
        env::current_dir()?.join(target)
    };
    if !target.exists() {
        return Ok(());
    }

    let mut history = load_history();
    history.retain(|path| path != &target);
    history.insert(0, target);
    history.truncate(HISTORY_LIMIT);

    let directory = cache_directory();
    fs::create_dir_all(&directory)?;
    let temporary = directory.join(format!("history.{}.tmp", std::process::id()));
    let mut data = Vec::new();
    for path in history {
        data.extend_from_slice(path.as_os_str().as_encoded_bytes());
        data.push(0);
    }
    if let Err(error) = fs::write(&temporary, data) {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    if let Err(error) = fs::rename(&temporary, history_path()) {
        let _ = fs::remove_file(&temporary);
        return Err(error);
    }
    Ok(())
}

fn cache_path() -> PathBuf {
    cache_directory().join("home-visible.nul")
}

fn load_home_candidates() -> io::Result<Vec<PathBuf>> {
    if !cache_path().is_file() {
        let status = Command::new(SEARCH)
            .arg("refresh")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()?;
        if !status.success() {
            return Err(io::Error::other(format!(
                "initial index refresh exited with {status}"
            )));
        }
    }
    let bytes = fs::read(cache_path())?;
    Ok(parse_nul_paths(bytes))
}

fn parse_nul_paths(bytes: Vec<u8>) -> Vec<PathBuf> {
    bytes
        .split(|byte| *byte == 0)
        .filter(|field| !field.is_empty())
        .map(|field| PathBuf::from(OsString::from_vec(field.to_vec())))
        .collect()
}

fn run_search(mode: &str, query: &str) -> io::Result<Vec<PathBuf>> {
    let output = Command::new(SEARCH)
        .arg(mode)
        .arg(query)
        .stdin(Stdio::null())
        .stderr(Stdio::null())
        .output()?;
    if !output.status.success() {
        return Err(io::Error::other(format!(
            "search exited with {}",
            output.status
        )));
    }
    Ok(parse_nul_paths(output.stdout))
}

fn classify_scope(query: &str, home: &Path) -> Scope {
    let relative = query.strip_prefix("~/").unwrap_or(query);
    if relative.starts_with('/') {
        let candidate = if relative == "/" {
            PathBuf::from("/")
        } else {
            Path::new(relative)
                .parent()
                .unwrap_or(Path::new("/"))
                .to_path_buf()
        };
        return if candidate.is_dir() {
            Scope::Exact(candidate.canonicalize().unwrap_or(candidate))
        } else {
            Scope::Filesystem
        };
    }

    let Some((directory, _)) = relative.rsplit_once('/') else {
        return Scope::Home;
    };
    let candidate = home.join(directory);
    if candidate.is_dir() {
        Scope::Exact(candidate.canonicalize().unwrap_or(candidate))
    } else {
        Scope::Home
    }
}

fn match_query<'a>(query: &'a str, scope: &Scope) -> &'a str {
    match scope {
        Scope::Exact(_) => query.rsplit('/').next().unwrap_or(query),
        Scope::Home | Scope::Filesystem => query.strip_prefix("~/").unwrap_or(query),
    }
}

fn requests_hidden(query: &str, scope: &Scope) -> bool {
    matches!(scope, Scope::Exact(_))
        && query
            .rsplit('/')
            .next()
            .is_some_and(|leaf| leaf.starts_with('.'))
}

fn sparse_results_need_hidden_fallback(matched: u32) -> bool {
    matched < HIDDEN_FALLBACK_THRESHOLD
}

fn display_query_path(path: &Path, home: &Path) -> String {
    if path == home {
        return "~".to_owned();
    }
    path.strip_prefix(home)
        .map(|relative| relative.to_string_lossy().into_owned())
        .unwrap_or_else(|_| path.to_string_lossy().into_owned())
}

fn display_result_path(path: &Path, home: &Path) -> String {
    path.strip_prefix(home)
        .map(|relative| format!("~/{}", relative.to_string_lossy()))
        .unwrap_or_else(|_| path.to_string_lossy().into_owned())
}

fn previous_boundary(text: &str, cursor: usize) -> usize {
    text[..cursor]
        .char_indices()
        .next_back()
        .map_or(0, |(index, _)| index)
}

fn next_boundary(text: &str, cursor: usize) -> usize {
    text[cursor..]
        .char_indices()
        .nth(1)
        .map_or(text.len(), |(offset, _)| cursor + offset)
}

fn char_width_before(text: &str, cursor: usize) -> usize {
    text[..cursor]
        .chars()
        .map(|character| character.width().unwrap_or(0))
        .sum()
}

fn truncate_left(text: &str, width: usize) -> String {
    if text.width() <= width {
        return text.to_owned();
    }
    if width <= 1 {
        return "…".chars().take(width).collect();
    }
    let mut kept = Vec::new();
    let mut used = 1;
    for character in text.chars().rev() {
        let character_width = character.width().unwrap_or(0);
        if used + character_width > width {
            break;
        }
        kept.push(character);
        used += character_width;
    }
    kept.reverse();
    format!("…{}", kept.into_iter().collect::<String>())
}

fn render(app: &mut App, frame: &mut Frame) {
    let area = frame.size();
    let outer = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .title(" Open ")
        .border_style(Style::default().fg(Color::DarkGray));
    let inner = outer.inner(area);
    frame.render_widget(outer, area);

    if inner.height < 3 || inner.width < 10 {
        return;
    }
    let sections = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(2),
            Constraint::Min(1),
            Constraint::Length(1),
        ])
        .split(inner);

    let scope_label = if app.query.starts_with('/') {
        "Filesystem › "
    } else {
        "Home › "
    };
    let rows = sections[1].height as u32;
    let (paths, matched, total, selected_row) = if app.matcher_stable {
        let snapshot = app.nucleo.snapshot();
        let matched = snapshot.matched_item_count();
        let selected = app.selected.min(matched.saturating_sub(1));
        let offset = if rows == 0 {
            0
        } else {
            selected - selected % rows
        };
        let end = (offset + rows).min(matched);
        let paths = if app.query.is_empty() && !app.recent_prefix.is_empty() {
            recent_match_page(snapshot, offset, end, &app.recent_prefix, &app.recent_set)
        } else {
            snapshot
                .matched_items(offset..end)
                .map(|item| item.data.clone())
                .collect::<Vec<_>>()
        };
        (
            paths,
            matched,
            snapshot.item_count(),
            (selected - offset) as usize,
        )
    } else {
        (
            app.display_paths.clone(),
            app.display_matched,
            app.display_total,
            app.display_selected_row,
        )
    };
    if app.matcher_stable {
        app.selected = app.selected.min(matched.saturating_sub(1));
        app.display_paths.clone_from(&paths);
        app.display_matched = matched;
        app.display_total = total;
        app.display_selected_row = selected_row;
    }

    let status = if app.refreshing {
        "refreshing index"
    } else if app.loading || app.nucleo.active_injectors() != 0 {
        "scanning"
    } else if !app.matcher_stable {
        "matching"
    } else if app.candidate_kind == CandidateKind::Fallback {
        "hidden/ignored"
    } else {
        ""
    };
    let count = format!(
        "{}{}/{}",
        if status.is_empty() {
            String::new()
        } else {
            format!("{status}  •  ")
        },
        matched,
        total
    );
    let prompt_width = sections[0].width.saturating_sub(count.width() as u16 + 1) as usize;
    let visible_query_width = prompt_width.saturating_sub(scope_label.width());
    let visible_query = truncate_left(&app.query, visible_query_width);
    let prompt = Paragraph::new(Line::from(vec![
        Span::styled(
            scope_label,
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(visible_query),
    ]));
    frame.render_widget(prompt, sections[0]);
    let count_area = Rect {
        x: sections[0].right().saturating_sub(count.width() as u16),
        y: sections[0].y,
        width: count.width() as u16,
        height: 1,
    };
    frame.render_widget(
        Paragraph::new(count).style(Style::default().fg(Color::DarkGray)),
        count_area,
    );

    let path_width = sections[1].width.saturating_sub(3) as usize;
    let items = paths.iter().map(|path| {
        ListItem::new(truncate_left(
            &display_result_path(path, &app.home),
            path_width,
        ))
    });
    let list = List::new(items).highlight_symbol("› ").highlight_style(
        Style::default()
            .fg(Color::Cyan)
            .add_modifier(Modifier::BOLD),
    );
    let mut state = ListState::default();
    if !paths.is_empty() {
        state.select(Some(selected_row.min(paths.len() - 1)));
    }
    frame.render_stateful_widget(list, sections[1], &mut state);

    let footer_text = app.message.as_deref().unwrap_or(
        "Enter open  •  Tab complete  •  ↑↓ select  •  / filesystem  •  Ctrl-R refresh  •  Esc cancel",
    );
    frame.render_widget(
        Paragraph::new(footer_text).style(Style::default().fg(if app.message.is_some() {
            Color::Yellow
        } else {
            Color::DarkGray
        })),
        sections[2],
    );

    // Keep the cursor stable even when the right-aligned count changes. If the
    // query is left-truncated, placing it at the prompt's right edge is the
    // closest visual representation of its true insertion point.
    let cursor_offset = char_width_before(&app.query, app.query_cursor);
    let cursor_x =
        sections[0].x + scope_label.width() as u16 + cursor_offset.min(visible_query_width) as u16;
    frame.set_cursor(
        cursor_x.min(sections[0].right().saturating_sub(1)),
        sections[0].y,
    );
}

struct TerminalGuard;

impl TerminalGuard {
    fn enter() -> io::Result<Self> {
        enable_raw_mode()?;
        execute!(
            io::stdout(),
            EnterAlternateScreen,
            EnableBracketedPaste,
            Hide
        )?;
        Ok(Self)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(
            io::stdout(),
            Show,
            DisableBracketedPaste,
            LeaveAlternateScreen
        );
    }
}

fn choose() -> io::Result<Option<PathBuf>> {
    let _guard = TerminalGuard::enter()?;
    let backend = CrosstermBackend::new(io::stdout());
    let mut terminal = Terminal::new(backend)?;
    terminal.clear()?;
    let mut app = App::new(home_directory());
    spawn_stale_refresh();
    let mut last_frame = Instant::now() - FRAME_INTERVAL;
    let mut needs_draw = true;

    loop {
        app.receive_candidates();
        let status = app.nucleo.tick(0);
        if !app.matcher_stable
            && !app.loading
            && app.nucleo.active_injectors() == 0
            && !status.running
        {
            app.matcher_stable = true;
            app.rebuild_recent_prefix();
            app.redraw_requested.store(true, Ordering::Release);
        }
        if app.matcher_stable && app.accept_when_stable {
            if let Some(selection) = app.selection() {
                return Ok(Some(selection));
            }
        }
        app.maybe_start_fallback(status.running);
        needs_draw |= app.redraw_requested.swap(false, Ordering::AcqRel);
        if needs_draw && last_frame.elapsed() >= FRAME_INTERVAL {
            terminal.draw(|frame| render(&mut app, frame))?;
            last_frame = Instant::now();
            needs_draw = false;
        }

        let timeout = if needs_draw {
            FRAME_INTERVAL.saturating_sub(last_frame.elapsed())
        } else {
            FRAME_INTERVAL
        };
        if !event::poll(timeout)? {
            continue;
        }
        match event::read()? {
            Event::Key(key) if key.kind == KeyEventKind::Press => {
                if let Some(selection) = handle_key(&mut app, key) {
                    return Ok(selection);
                }
            }
            Event::Paste(text) => app.insert(&text),
            Event::Resize(_, _) => app.redraw_requested.store(true, Ordering::Release),
            _ => {}
        }
    }
}

fn handle_key(app: &mut App, key: KeyEvent) -> Option<Option<PathBuf>> {
    match (key.code, key.modifiers) {
        (KeyCode::Esc, _) | (KeyCode::Char('c'), KeyModifiers::CONTROL) => Some(None),
        (KeyCode::Enter, _) => {
            if app.matcher_stable {
                app.selection().map(Some)
            } else {
                app.accept_when_stable = true;
                app.message = Some("Waiting for the current search to finish…".to_owned());
                app.redraw_requested.store(true, Ordering::Release);
                None
            }
        }
        (KeyCode::Tab, _) => {
            app.complete_selection();
            None
        }
        (KeyCode::Up, _) | (KeyCode::Char('p'), KeyModifiers::CONTROL) => {
            app.move_selection(1, false);
            None
        }
        (KeyCode::Down, _) | (KeyCode::Char('n'), KeyModifiers::CONTROL) => {
            app.move_selection(1, true);
            None
        }
        (KeyCode::PageUp, _) => {
            app.move_selection(10, false);
            None
        }
        (KeyCode::PageDown, _) => {
            app.move_selection(10, true);
            None
        }
        (KeyCode::Left, _) => {
            app.query_cursor = previous_boundary(&app.query, app.query_cursor);
            app.redraw_requested.store(true, Ordering::Release);
            None
        }
        (KeyCode::Right, _) => {
            app.query_cursor = next_boundary(&app.query, app.query_cursor);
            app.redraw_requested.store(true, Ordering::Release);
            None
        }
        (KeyCode::Home, _) | (KeyCode::Char('a'), KeyModifiers::CONTROL) => {
            app.query_cursor = 0;
            app.redraw_requested.store(true, Ordering::Release);
            None
        }
        (KeyCode::End, _) | (KeyCode::Char('e'), KeyModifiers::CONTROL) => {
            app.query_cursor = app.query.len();
            app.redraw_requested.store(true, Ordering::Release);
            None
        }
        (KeyCode::Backspace, _) => {
            app.backspace();
            None
        }
        (KeyCode::Delete, _) => {
            app.delete();
            None
        }
        (KeyCode::Char('w'), KeyModifiers::CONTROL) => {
            app.delete_word();
            None
        }
        (KeyCode::Char('u'), KeyModifiers::CONTROL) => {
            let old = app.query.clone();
            app.query.drain(..app.query_cursor);
            app.query_cursor = 0;
            app.query_changed(&old);
            None
        }
        (KeyCode::Char('r'), KeyModifiers::CONTROL) => {
            app.refresh_index();
            None
        }
        (KeyCode::Char(character), modifiers)
            if !modifiers.intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
        {
            app.insert(&character.to_string());
            None
        }
        _ => None,
    }
}

fn spawn_stale_refresh() {
    thread::spawn(|| {
        let _ = Command::new(SEARCH)
            .arg("refresh-if-stale")
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status();
    });
}

fn report_open_error(target: &OsStr, log_path: &Path) {
    eprintln!(
        "Could not open {:?}. Diagnostics were saved to {}.",
        target,
        log_path.display()
    );
}

fn open_targets(targets: &[OsString]) -> io::Result<bool> {
    if env::var_os("OPEN_FILE_PICKER_DRY_RUN").as_deref() == Some(OsStr::new("1")) {
        let mut stdout = io::stdout().lock();
        for target in targets {
            stdout.write_all(target.as_encoded_bytes())?;
            stdout.write_all(&[0])?;
        }
        return Ok(false);
    }

    fs::create_dir_all(cache_directory())?;
    let log_path = cache_directory().join("open-errors.log");
    let mut failed = false;
    for target in targets {
        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&log_path)?;
        let stderr = log.try_clone()?;
        let status = Command::new(SETSID)
            .args(["--fork", "--wait", GIO, "open"])
            .arg(target)
            .stdin(Stdio::null())
            .stdout(Stdio::from(log))
            .stderr(Stdio::from(stderr))
            .status()?;
        if !status.success() {
            failed = true;
            report_open_error(target, &log_path);
        } else {
            let _ = record_history(target);
        }
    }
    Ok(failed)
}

fn refresh_index_only() -> io::Result<bool> {
    Ok(!Command::new(SEARCH).arg("refresh").status()?.success())
}

fn main() -> ExitCode {
    let arguments: Vec<OsString> = env::args_os().skip(1).collect();
    let result = if arguments.len() == 1 && arguments[0] == "--refresh-index" {
        refresh_index_only()
    } else if !arguments.is_empty() {
        open_targets(&arguments)
    } else {
        choose().and_then(|selection| {
            selection.map_or(Ok(false), |path| open_targets(&[path.into_os_string()]))
        })
    };

    match result {
        Ok(false) => ExitCode::SUCCESS,
        Ok(true) => ExitCode::FAILURE,
        Err(error) => {
            eprintln!("open-file-picker: {error}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nul_paths_preserve_non_utf8_bytes() {
        let paths = parse_nul_paths(b"/tmp/one\0/tmp/tw\x80\0".to_vec());
        assert_eq!(paths.len(), 2);
        assert_eq!(paths[0], Path::new("/tmp/one"));
        assert_eq!(paths[1].as_os_str().as_encoded_bytes(), b"/tmp/tw\x80");
    }

    #[test]
    fn query_uses_only_the_leaf_in_an_exact_scope() {
        assert_eq!(
            match_query("code/project/nee", &Scope::Exact(PathBuf::from("/tmp"))),
            "nee"
        );
        assert_eq!(match_query("needle", &Scope::Home), "needle");
    }

    #[test]
    fn truncation_keeps_the_filename() {
        assert_eq!(truncate_left("/long/path/file.png", 10), "…/file.png");
    }

    #[test]
    fn hidden_directory_is_ranked_for_dot_prefix() {
        use nucleo::pattern::Pattern;
        use nucleo::Matcher;

        let pattern = Pattern::parse(".g", CaseMatching::Smart, Normalization::Smart);
        let mut matcher = Matcher::new(Config::DEFAULT.match_paths());
        let matches = pattern.match_list(
            [
                "/home/me/project/wallpaper_dark.jpg",
                "/home/me/project/.git",
            ],
            &mut matcher,
        );
        assert_eq!(matches[0].0, "/home/me/project/.git");
    }

    #[test]
    fn dot_prefix_changes_the_exact_scope_candidate_policy() {
        let scope = Scope::Exact(PathBuf::from("/home/me/project"));
        assert!(!requests_hidden("project/", &scope));
        assert!(requests_hidden("project/.g", &scope));
    }

    #[test]
    fn hidden_fallback_is_limited_to_sparse_results() {
        assert!(sparse_results_need_hidden_fallback(0));
        assert!(sparse_results_need_hidden_fallback(19));
        assert!(!sparse_results_need_hidden_fallback(20));
        assert!(!sparse_results_need_hidden_fallback(21));
    }

    #[test]
    fn recent_paths_are_injected_before_unvisited_paths() {
        let history = HashMap::from([
            (PathBuf::from("/home/me/second"), 1),
            (PathBuf::from("/home/me/first"), 0),
        ]);
        let paths = prioritize_paths(
            vec![
                PathBuf::from("/home/me/other"),
                PathBuf::from("/home/me/second"),
                PathBuf::from("/home/me/first"),
            ],
            &history,
        );
        assert_eq!(
            paths,
            vec![
                PathBuf::from("/home/me/first"),
                PathBuf::from("/home/me/second"),
                PathBuf::from("/home/me/other"),
            ]
        );
    }
}
