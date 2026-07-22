//! karo: one front-end for every task runner.
//!
//! `karo` lists tasks from whatever runners a project uses (just, package.json
//! scripts, deno tasks, go-task, make, uv) and `karo <task>` exec()s the real
//! tool. All parsing/execution semantics stay in the underlying tools: listing
//! is delegated too where the tool supports it (`just --dump`,
//! `task --list-all --json`, `make -pRrq`).

use std::collections::BTreeSet;
use std::env;
use std::fs;
use std::io::IsTerminal;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{exit, Command, Stdio};

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Clone, Copy, PartialEq, Eq, Debug, Hash)]
enum Kind {
    Just,
    Pkg,
    Deno,
    GoTask,
    Make,
    Uv,
}

const ALL_KINDS: [Kind; 6] = [
    Kind::Just,
    Kind::Pkg,
    Kind::Deno,
    Kind::GoTask,
    Kind::Make,
    Kind::Uv,
];

struct Runner {
    kind: Kind,
    /// Short id used for `id:task` qualification (e.g. "just", "bun", "make").
    id: String,
    /// Binary that will be exec'd. Usually same as `id`, but go-task may be
    /// installed as `go-task` when plain `task` is taskwarrior.
    bin: String,
    manifest: PathBuf,
    dir: PathBuf,
}

struct TaskEntry {
    name: String,
    desc: String,
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let cwd = env::current_dir().unwrap_or_else(|e| die(&format!("cannot get cwd: {e}")));

    match args.first().map(String::as_str) {
        None | Some("--list") | Some("-l") => list_all(&cwd),
        Some("--help") | Some("-h") => print_help(),
        Some("--version") | Some("-V") => println!("karo {VERSION}"),
        Some("--complete-tasks") => complete_tasks(&cwd),
        Some(name) => run_task(&cwd, name, &args[1..]),
    }
}

fn print_help() {
    println!(
        "\
karo {VERSION} — one front-end for every task runner

Usage:
  karo                    list tasks from all runners found here (walking up)
  karo <task> [args...]   run a task by delegating to the owning runner
  karo <runner>:<task>    disambiguate when multiple runners define the task
  karo -l | --list        same as bare `karo`

Supported runners (nearest manifest wins, all can coexist):
  just                justfile / .justfile
  bun|npm|pnpm|yarn   package.json scripts (picked via packageManager field
                      or lockfile: bun.lock > pnpm-lock.yaml > yarn.lock >
                      package-lock.json; defaults to bun)
  deno                deno.json / deno.jsonc tasks
  task                Taskfile.yml (go-task)
  make                Makefile targets (from `make -pRrq` database)
  uv                  pyproject.toml [project.scripts]

Examples:
  karo build            # -> `just build` or `bun run build` or `make build` ...
  karo just:test        # force the just runner
  karo dev --port 3000  # extra args are forwarded to the task

Internal:
  karo --complete-tasks   print `name<TAB>description` lines for shell completion"
    );
}

// ---------------------------------------------------------------------------
// Discovery
// ---------------------------------------------------------------------------

fn discover(cwd: &Path) -> Vec<Runner> {
    let mut runners = Vec::new();
    let mut seen: BTreeSet<u8> = BTreeSet::new();
    for dir in cwd.ancestors() {
        for (i, kind) in ALL_KINDS.iter().enumerate() {
            if seen.contains(&(i as u8)) {
                continue;
            }
            if let Some(r) = detect(*kind, dir) {
                seen.insert(i as u8);
                runners.push(r);
            }
        }
    }
    runners
}

fn first_existing(dir: &Path, names: &[&str]) -> Option<PathBuf> {
    names.iter().map(|n| dir.join(n)).find(|p| p.is_file())
}

fn detect(kind: Kind, dir: &Path) -> Option<Runner> {
    let mk = |id: &str, manifest: PathBuf| Runner {
        kind,
        id: id.to_string(),
        bin: id.to_string(),
        manifest,
        dir: dir.to_path_buf(),
    };
    match kind {
        Kind::Just => {
            first_existing(dir, &["justfile", "Justfile", ".justfile"]).map(|m| mk("just", m))
        }
        Kind::Pkg => {
            let m = dir.join("package.json");
            let text = fs::read_to_string(&m).ok()?;
            let v: serde_json::Value = serde_json::from_str(&text).ok()?;
            let scripts = v.get("scripts")?.as_object()?;
            if scripts.is_empty() {
                return None;
            }
            let pm = choose_pkg_manager(dir, &v);
            Some(mk(pm, m))
        }
        Kind::Deno => {
            let m = first_existing(dir, &["deno.json", "deno.jsonc"])?;
            let text = fs::read_to_string(&m).ok()?;
            let v = parse_jsonc(&text)?;
            let tasks = v.get("tasks")?.as_object()?;
            if tasks.is_empty() {
                return None;
            }
            Some(mk("deno", m))
        }
        Kind::GoTask => first_existing(
            dir,
            &[
                "Taskfile.yml",
                "Taskfile.yaml",
                "taskfile.yml",
                "taskfile.yaml",
                "Taskfile.dist.yml",
                "Taskfile.dist.yaml",
            ],
        )
        .map(|m| {
            let mut r = mk("task", m);
            r.bin = gotask_bin();
            r
        }),
        Kind::Make => {
            first_existing(dir, &["GNUmakefile", "makefile", "Makefile"]).map(|m| mk("make", m))
        }
        Kind::Uv => {
            let m = dir.join("pyproject.toml");
            let text = fs::read_to_string(&m).ok()?;
            let v: toml::Value = text.parse().ok()?;
            let scripts = v.get("project")?.get("scripts")?.as_table()?;
            if scripts.is_empty() {
                return None;
            }
            Some(mk("uv", m))
        }
    }
}

fn choose_pkg_manager(dir: &Path, pkg: &serde_json::Value) -> &'static str {
    if let Some(pm) = pkg
        .get("packageManager")
        .and_then(|v| v.as_str())
        .and_then(pm_from_field)
    {
        return pm;
    }
    for (lock, pm) in [
        ("bun.lock", "bun"),
        ("bun.lockb", "bun"),
        ("pnpm-lock.yaml", "pnpm"),
        ("yarn.lock", "yarn"),
        ("package-lock.json", "npm"),
    ] {
        if dir.join(lock).is_file() {
            return pm;
        }
    }
    "bun"
}

/// go-task installs its binary as `task`, which collides with taskwarrior.
/// Verify via `--version` output; fall back to the unambiguous `go-task`
/// name so we never accidentally exec taskwarrior.
fn gotask_bin() -> String {
    for cand in ["task", "go-task"] {
        let out = Command::new(cand)
            .arg("--version")
            .stdin(Stdio::null())
            .output();
        if let Ok(out) = out {
            if String::from_utf8_lossy(&out.stdout).contains("Task version") {
                return cand.to_string();
            }
        }
    }
    "go-task".to_string()
}

/// Parses a package.json `packageManager` field like "pnpm@9.1.0".
fn pm_from_field(field: &str) -> Option<&'static str> {
    let name = field.split('@').next().unwrap_or("");
    ["bun", "pnpm", "yarn", "npm"]
        .into_iter()
        .find(|&pm| pm == name)
}

// ---------------------------------------------------------------------------
// Task listing (delegated to the tool itself where possible)
// ---------------------------------------------------------------------------

fn list_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    match r.kind {
        Kind::Just => just_tasks(r),
        Kind::Pkg => pkg_tasks(r),
        Kind::Deno => deno_tasks(r),
        Kind::GoTask => gotask_tasks(r),
        Kind::Make => make_tasks(r),
        Kind::Uv => uv_tasks(r),
    }
}

fn run_capture(dir: &Path, bin: &str, args: &[&str]) -> Result<(bool, String, String), String> {
    let out = Command::new(bin)
        .args(args)
        .current_dir(dir)
        .stdin(Stdio::null())
        .output()
        .map_err(|e| format!("cannot run `{bin}`: {e}"))?;
    Ok((
        out.status.success(),
        String::from_utf8_lossy(&out.stdout).into_owned(),
        String::from_utf8_lossy(&out.stderr).into_owned(),
    ))
}

fn just_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    let (ok, stdout, stderr) = run_capture(&r.dir, "just", &["--dump", "--dump-format", "json"])?;
    if !ok {
        return Err(format!("just --dump failed: {}", stderr.trim()));
    }
    let v: serde_json::Value =
        serde_json::from_str(&stdout).map_err(|e| format!("bad json from just: {e}"))?;
    let recipes = v
        .get("recipes")
        .and_then(|r| r.as_object())
        .ok_or("no recipes in just dump")?;
    let mut tasks = Vec::new();
    for (name, recipe) in recipes {
        let private = recipe.get("private").and_then(|p| p.as_bool()).unwrap_or(false);
        if private || name.starts_with('_') {
            continue;
        }
        let doc = recipe
            .get("doc")
            .and_then(|d| d.as_str())
            .unwrap_or("")
            .to_string();
        let params: Vec<String> = recipe
            .get("parameters")
            .and_then(|p| p.as_array())
            .map(|ps| {
                ps.iter()
                    .filter_map(|p| p.get("name").and_then(|n| n.as_str()))
                    .map(|n| format!("<{n}>"))
                    .collect()
            })
            .unwrap_or_default();
        let desc = if params.is_empty() {
            doc
        } else if doc.is_empty() {
            params.join(" ")
        } else {
            format!("{} — {doc}", params.join(" "))
        };
        tasks.push(TaskEntry {
            name: name.clone(),
            desc,
        });
    }
    tasks.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(tasks)
}

fn pkg_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    let text = fs::read_to_string(&r.manifest).map_err(|e| e.to_string())?;
    let v: serde_json::Value = serde_json::from_str(&text).map_err(|e| e.to_string())?;
    let scripts = v
        .get("scripts")
        .and_then(|s| s.as_object())
        .ok_or("no scripts in package.json")?;
    Ok(scripts
        .iter()
        .map(|(name, cmd)| TaskEntry {
            name: name.clone(),
            desc: truncate(cmd.as_str().unwrap_or(""), 72),
        })
        .collect())
}

fn deno_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    let text = fs::read_to_string(&r.manifest).map_err(|e| e.to_string())?;
    let v = parse_jsonc(&text).ok_or("cannot parse deno config")?;
    let tasks = v
        .get("tasks")
        .and_then(|t| t.as_object())
        .ok_or("no tasks in deno config")?;
    Ok(tasks
        .iter()
        .map(|(name, val)| {
            let desc = match val {
                serde_json::Value::String(s) => s.clone(),
                obj => obj
                    .get("description")
                    .or_else(|| obj.get("command"))
                    .and_then(|d| d.as_str())
                    .unwrap_or("")
                    .to_string(),
            };
            TaskEntry {
                name: name.clone(),
                desc: truncate(&desc, 72),
            }
        })
        .collect())
}

fn gotask_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    let (ok, stdout, _) = run_capture(&r.dir, &r.bin, &["--list-all", "--json"])?;
    if ok {
        if let Ok(v) = serde_json::from_str::<serde_json::Value>(&stdout) {
            if let Some(items) = v.get("tasks").and_then(|t| t.as_array()) {
                let mut tasks: Vec<TaskEntry> = items
                    .iter()
                    .filter_map(|t| {
                        let name = t.get("name")?.as_str()?.to_string();
                        let desc = t
                            .get("desc")
                            .and_then(|d| d.as_str())
                            .unwrap_or("")
                            .to_string();
                        Some(TaskEntry { name, desc })
                    })
                    .collect();
                tasks.sort_by(|a, b| a.name.cmp(&b.name));
                return Ok(tasks);
            }
        }
    }
    // Older go-task without --json support.
    let (ok, stdout, stderr) = run_capture(&r.dir, &r.bin, &["--list-all"])?;
    if !ok {
        return Err(format!("{} --list-all failed: {}", r.bin, stderr.trim()));
    }
    let mut tasks = Vec::new();
    for line in stdout.lines() {
        let Some(rest) = line.trim_start().strip_prefix("* ") else {
            continue;
        };
        let (name, desc) = match rest.find(": ") {
            Some(i) => (&rest[..i], rest[i + 2..].trim()),
            None => (rest.trim_end_matches(':'), ""),
        };
        tasks.push(TaskEntry {
            name: name.to_string(),
            desc: desc.to_string(),
        });
    }
    tasks.sort_by(|a, b| a.name.cmp(&b.name));
    Ok(tasks)
}

fn make_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    // -p prints make's own parsed database, -q avoids running anything,
    // -Rr strips builtin rules/variables. Exit code is meaningless in -q mode.
    let (_, stdout, stderr) = run_capture(&r.dir, "make", &["-pRrq"])?;
    if stdout.is_empty() {
        return Err(format!("make -p produced no output: {}", stderr.trim()));
    }
    Ok(parse_make_db(&stdout)
        .into_iter()
        .map(|name| TaskEntry {
            name,
            desc: String::new(),
        })
        .collect())
}

fn parse_make_db(out: &str) -> Vec<String> {
    let mut names = BTreeSet::new();
    let mut not_target = false;
    for line in out.lines() {
        if line == "# Not a target:" {
            not_target = true;
            continue;
        }
        let skip = std::mem::replace(&mut not_target, false);
        if line.is_empty() || line.starts_with('#') || line.starts_with('\t') || line.starts_with(' ')
        {
            continue;
        }
        let Some(colon) = line.find(':') else { continue };
        if line.as_bytes().get(colon + 1) == Some(&b'=') {
            continue; // `VAR := value` assignment, not a rule
        }
        if skip {
            continue;
        }
        let name = line[..colon].trim();
        if name.is_empty()
            || name.starts_with('.')
            || name.contains('%')
            || name.contains('=')
            || name.contains(' ')
            || name.contains('/')
            || matches!(name, "Makefile" | "makefile" | "GNUmakefile")
        {
            continue;
        }
        names.insert(name.to_string());
    }
    names.into_iter().collect()
}

fn uv_tasks(r: &Runner) -> Result<Vec<TaskEntry>, String> {
    let text = fs::read_to_string(&r.manifest).map_err(|e| e.to_string())?;
    let v: toml::Value = text.parse().map_err(|e| format!("bad pyproject.toml: {e}"))?;
    let scripts = v
        .get("project")
        .and_then(|p| p.get("scripts"))
        .and_then(|s| s.as_table())
        .ok_or("no [project.scripts] in pyproject.toml")?;
    Ok(scripts
        .iter()
        .map(|(name, val)| TaskEntry {
            name: name.clone(),
            desc: truncate(val.as_str().unwrap_or(""), 72),
        })
        .collect())
}

// ---------------------------------------------------------------------------
// Listing UI
// ---------------------------------------------------------------------------

fn list_all(cwd: &Path) -> ! {
    let runners = discover(cwd);
    if runners.is_empty() {
        die(
            "no task runners found here (looked for: justfile, package.json scripts, \
             deno.json tasks, Taskfile.yml, Makefile, pyproject.toml [project.scripts])",
        );
    }
    let p = Paint(std::io::stdout().is_terminal());
    for r in &runners {
        println!(
            "{} {}",
            p.bold_cyan(&r.id),
            p.dim(&format!("· {}", rel_display(&r.manifest, cwd)))
        );
        match list_tasks(r) {
            Ok(tasks) if tasks.is_empty() => println!("  {}", p.dim("(no tasks)")),
            Ok(tasks) => {
                let width = tasks.iter().map(|t| t.name.len()).max().unwrap_or(0).min(28);
                for t in tasks {
                    if t.desc.is_empty() {
                        println!("  {}", t.name);
                    } else {
                        println!("  {:<width$}  {}", t.name, p.dim(&t.desc), width = width);
                    }
                }
            }
            Err(e) => println!("  {}", p.dim(&format!("! {e}"))),
        }
        println!();
    }
    println!(
        "{}",
        p.dim("karo <task> [args...]   ·   karo <runner>:<task> to disambiguate")
    );
    exit(0)
}

fn rel_display(path: &Path, cwd: &Path) -> String {
    if let Ok(p) = path.strip_prefix(cwd) {
        return p.display().to_string();
    }
    let mut base = cwd;
    let mut ups = 0;
    while let Some(parent) = base.parent() {
        ups += 1;
        base = parent;
        if let Ok(p) = path.strip_prefix(base) {
            return format!("{}{}", "../".repeat(ups), p.display());
        }
    }
    path.display().to_string()
}

struct Paint(bool);

impl Paint {
    fn wrap(&self, code: &str, s: &str) -> String {
        if self.0 {
            format!("\x1b[{code}m{s}\x1b[0m")
        } else {
            s.to_string()
        }
    }
    fn bold_cyan(&self, s: &str) -> String {
        self.wrap("1;36", s)
    }
    fn dim(&self, s: &str) -> String {
        self.wrap("2", s)
    }
}

fn truncate(s: &str, max: usize) -> String {
    let s = s.trim();
    if s.chars().count() <= max {
        s.to_string()
    } else {
        let cut: String = s.chars().take(max - 1).collect();
        format!("{cut}…")
    }
}

// ---------------------------------------------------------------------------
// Running
// ---------------------------------------------------------------------------

fn run_task(cwd: &Path, name: &str, extra: &[String]) -> ! {
    let runners = discover(cwd);
    if runners.is_empty() {
        die("no task runners found here (run `karo --help` for what is searched)");
    }

    // Qualified form: `karo just:build`. Only if the prefix is an actual
    // runner id, since task names themselves may contain ':' (go-task
    // namespaces).
    if let Some((prefix, rest)) = name.split_once(':') {
        if let Some(r) = runners.iter().find(|r| r.id == prefix) {
            exec_task(r, rest, extra);
        }
    }

    let mut owners: Vec<&Runner> = Vec::new();
    let mut list_errors: Vec<(String, String)> = Vec::new();
    for r in &runners {
        match list_tasks(r) {
            Ok(tasks) => {
                if tasks.iter().any(|t| t.name == name) {
                    owners.push(r);
                }
            }
            Err(e) => list_errors.push((r.id.clone(), e)),
        }
    }

    match owners.len() {
        1 => exec_task(owners[0], name, extra),
        0 => {
            // Unknown to us but there's a single runner: pass through and let
            // the real tool produce its own (usually better) error/suggestion.
            if runners.len() == 1 {
                exec_task(&runners[0], name, extra);
            }
            for (id, e) in &list_errors {
                eprintln!("karo: note: could not list {id} tasks: {e}");
            }
            die(&format!(
                "no runner here defines task `{name}` (try bare `karo` to list tasks, \
                 or `<runner>:{name}` to force a pass-through)"
            ));
        }
        _ => {
            eprintln!("karo: task `{name}` is defined by multiple runners, pick one:");
            for r in owners {
                eprintln!("  karo {}:{name}", r.id);
            }
            exit(1)
        }
    }
}

fn exec_task(r: &Runner, task: &str, extra: &[String]) -> ! {
    let mut cmd = Command::new(&r.bin);
    match r.kind {
        Kind::Just => {
            // `--` so that recipe arguments starting with '-' are not eaten
            // as just's own flags.
            if extra.iter().any(|a| a.starts_with('-')) {
                cmd.arg("--");
            }
            cmd.arg(task).args(extra);
        }
        Kind::Pkg => {
            cmd.arg("run").arg(task);
            if r.id == "npm" && !extra.is_empty() {
                cmd.arg("--");
            }
            cmd.args(extra);
        }
        Kind::Deno => {
            cmd.arg("task").arg(task).args(extra);
        }
        Kind::GoTask => {
            cmd.arg(task);
            if !extra.is_empty() {
                cmd.arg("--").args(extra);
            }
        }
        Kind::Make => {
            // make does not walk up to find its Makefile, so point it there.
            cmd.arg("-C").arg(&r.dir).arg(task).args(extra);
        }
        Kind::Uv => {
            cmd.arg("run").arg(task).args(extra);
        }
    }

    let rendered: Vec<String> = std::iter::once(r.bin.clone())
        .chain(cmd.get_args().map(|a| a.to_string_lossy().into_owned()))
        .map(|a| {
            if a.contains(' ') {
                format!("'{a}'")
            } else {
                a
            }
        })
        .collect();
    let p = Paint(std::io::stderr().is_terminal());
    eprintln!("{}", p.dim(&format!("karo → {}", rendered.join(" "))));

    let err = cmd.exec();
    eprintln!("karo: failed to exec `{}`: {err}", r.bin);
    exit(127)
}

fn die(msg: &str) -> ! {
    eprintln!("karo: {msg}");
    exit(1)
}

/// Prints `name<TAB>description` lines for shell completion scripts. Names
/// defined by multiple runners are emitted in their qualified `runner:name`
/// form, since that is what will actually run. Never fails: completion must
/// stay silent on errors.
fn complete_tasks(cwd: &Path) -> ! {
    let runners = discover(cwd);
    let per: Vec<(&Runner, Vec<TaskEntry>)> = runners
        .iter()
        .filter_map(|r| list_tasks(r).ok().map(|tasks| (r, tasks)))
        .collect();

    let mut counts: std::collections::HashMap<&str, usize> = Default::default();
    for (_, tasks) in &per {
        for t in tasks {
            *counts.entry(t.name.as_str()).or_default() += 1;
        }
    }

    for (r, tasks) in &per {
        for t in tasks {
            let name = if counts[t.name.as_str()] > 1 {
                format!("{}:{}", r.id, t.name)
            } else {
                t.name.clone()
            };
            let desc: String = t
                .desc
                .chars()
                .map(|c| if c == '\t' || c == '\n' { ' ' } else { c })
                .collect();
            if desc.is_empty() {
                println!("{name}");
            } else {
                println!("{name}\t{desc}");
            }
        }
    }
    exit(0)
}

// ---------------------------------------------------------------------------
// JSONC (deno.jsonc) support: strip comments and trailing commas, then parse.
// ---------------------------------------------------------------------------

fn parse_jsonc(text: &str) -> Option<serde_json::Value> {
    serde_json::from_str(&strip_jsonc(text)).ok()
}

fn strip_jsonc(text: &str) -> String {
    // Pass 1: drop // and /* */ comments (string-aware).
    let chars: Vec<char> = text.chars().collect();
    let mut no_comments = String::with_capacity(text.len());
    let mut i = 0;
    let mut in_str = false;
    while i < chars.len() {
        let c = chars[i];
        if in_str {
            no_comments.push(c);
            if c == '\\' {
                if let Some(&n) = chars.get(i + 1) {
                    no_comments.push(n);
                    i += 2;
                    continue;
                }
            } else if c == '"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        match c {
            '"' => {
                in_str = true;
                no_comments.push(c);
                i += 1;
            }
            '/' if chars.get(i + 1) == Some(&'/') => {
                while i < chars.len() && chars[i] != '\n' {
                    i += 1;
                }
            }
            '/' if chars.get(i + 1) == Some(&'*') => {
                i += 2;
                while i + 1 < chars.len() && !(chars[i] == '*' && chars[i + 1] == '/') {
                    i += 1;
                }
                i = (i + 2).min(chars.len());
            }
            _ => {
                no_comments.push(c);
                i += 1;
            }
        }
    }

    // Pass 2: drop trailing commas before } or ] (string-aware).
    let chars: Vec<char> = no_comments.chars().collect();
    let mut out = String::with_capacity(no_comments.len());
    let mut i = 0;
    let mut in_str = false;
    while i < chars.len() {
        let c = chars[i];
        if in_str {
            out.push(c);
            if c == '\\' {
                if let Some(&n) = chars.get(i + 1) {
                    out.push(n);
                    i += 2;
                    continue;
                }
            } else if c == '"' {
                in_str = false;
            }
            i += 1;
            continue;
        }
        if c == '"' {
            in_str = true;
        } else if c == ',' {
            let mut j = i + 1;
            while j < chars.len() && chars[j].is_whitespace() {
                j += 1;
            }
            if matches!(chars.get(j), Some('}') | Some(']')) {
                i += 1;
                continue;
            }
        }
        out.push(c);
        i += 1;
    }
    out
}

// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn make_db_parsing() {
        let db = r#"# GNU Make 4.4.1
# Variables

SHELL = /bin/sh
CURDIR := /home/x
MAKEFLAGS = pqrR

# Files

all: build

# Not a target:
.SUFFIXES:

build:
	echo building

%.o: %.c

obj/main.o: src/main.c

Makefile:

# Not a target:
helper.sh:

clean:
	rm -rf out

.PHONY: all build clean
"#;
        assert_eq!(parse_make_db(db), vec!["all", "build", "clean"]);
    }

    #[test]
    fn jsonc_parsing() {
        let text = r#"{
  // dev tasks
  "tasks": {
    "dev": "deno run -A main.ts", /* watch mode elsewhere */
    "url": "echo https://example.com", // not a comment inside the string
  },
}"#;
        let v = parse_jsonc(text).unwrap();
        let tasks = v.get("tasks").unwrap().as_object().unwrap();
        assert_eq!(tasks.len(), 2);
        assert_eq!(
            tasks.get("url").unwrap().as_str().unwrap(),
            "echo https://example.com"
        );
    }

    #[test]
    fn package_manager_field() {
        assert_eq!(pm_from_field("pnpm@9.1.0"), Some("pnpm"));
        assert_eq!(pm_from_field("bun@1.2.0"), Some("bun"));
        assert_eq!(pm_from_field("something@1.0"), None);
    }
}
