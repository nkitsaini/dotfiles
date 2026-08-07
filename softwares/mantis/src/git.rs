use crate::{
    db::Database,
    logging::Logger,
    model::{ConflictFile, RecentCommit, Repository, SyncResult},
    paths::AppPaths,
};
use anyhow::{Context, Result};
use chrono::Utc;
use std::{
    fs::{File, OpenOptions},
    io::Read,
    path::Path,
    process::{Command, Output},
    thread,
    time::{Duration, Instant},
};

pub async fn sync_repository(
    db: &Database,
    logger: &Logger,
    paths: &AppPaths,
    repo: &Repository,
) -> Result<SyncResult> {
    let db = db.clone();
    let logger = logger.clone();
    let paths = paths.clone();
    let repo = repo.clone();
    tokio::task::spawn_blocking(move || sync_blocking(&db, &logger, &paths, &repo)).await?
}

pub fn trust_worktree_ownership(worktree: &str) -> Result<()> {
    let path = std::fs::canonicalize(worktree)
        .with_context(|| format!("resolving content directory {worktree}"))?;
    let value = path.to_string_lossy();
    let existing = Command::new("git")
        .args(["config", "--global", "--get-all", "safe.directory"])
        .output()
        .context("reading Git safe.directory configuration")?;
    if String::from_utf8_lossy(&existing.stdout)
        .lines()
        .any(|entry| entry == value)
    {
        return Ok(());
    }
    let output = Command::new("git")
        .args(["config", "--global", "--add", "safe.directory"])
        .arg(path)
        .output()
        .context("updating Git safe.directory configuration")?;
    if !output.status.success() {
        anyhow::bail!(
            "could not mark the content directory as safe: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(())
}

fn sync_blocking(
    db: &Database,
    logger: &Logger,
    paths: &AppPaths,
    repo: &Repository,
) -> Result<SyncResult> {
    let lock_path = paths.lock_dir.join(format!("{}.lock", repo.id));
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(lock_path)?;
    if !try_lock(&lock)? {
        logger.log(
            "error",
            "Synchronization could not start because another Mantis process holds the repository lock",
            Some(&repo.id),
        );
        anyhow::bail!("repository is already synchronizing");
    }
    db.set_sync_started(&repo.id)?;
    logger.log("info", "Synchronization started", Some(&repo.id));

    let result = perform_sync(db, logger, paths, repo);
    if let Err(error) = &result {
        let message = format!("{error:#}");
        let attention = has_unmerged(repo).unwrap_or(false);
        let status = if attention {
            "needs_attention"
        } else {
            "failed"
        };
        let failures = db.set_sync_failure(&repo.id, status, &message).unwrap_or(1);
        logger.log("error", &message, Some(&repo.id));
        if attention || is_notification_point(failures) {
            notify(logger, repo, status, &message, attention);
        }
    }
    result
}

fn perform_sync(
    db: &Database,
    logger: &Logger,
    paths: &AppPaths,
    repo: &Repository,
) -> Result<SyncResult> {
    verify_repository(repo)?;
    if has_unmerged(repo)? {
        anyhow::bail!("repository has unresolved merge conflicts");
    }

    let changes = status_paths(repo)?;
    let mut skipped = Vec::new();
    let mut eligible = Vec::new();
    for path in changes {
        let absolute = Path::new(&repo.worktree).join(&path);
        if absolute.is_file() && is_binary(&absolute)? {
            skipped.push(path);
        } else {
            eligible.push(path);
        }
    }
    if !skipped.is_empty() {
        logger.log(
            "warning",
            &format!("Skipped binary files: {}", skipped.join(", ")),
            Some(&repo.id),
        );
        if skipped != repo.skipped_binaries {
            notify(
                logger,
                repo,
                "needs_attention",
                &format!("Skipped {} binary file(s)", skipped.len()),
                false,
            );
        }
    }
    for path in &eligible {
        git(repo, &["add", "--", path])?;
    }

    let committed = !git_status(repo, &["diff", "--cached", "--quiet"])?.success();
    if committed {
        git(
            repo,
            &[
                "commit",
                "-m",
                &format!("Auto-sync: {}", Utc::now().to_rfc3339()),
            ],
        )?;
        logger.log("info", "Committed local text changes", Some(&repo.id));
    }

    let credential = match &repo.credential_id {
        Some(id) => Some(db.get_credential(id)?),
        None => None,
    };
    logger.log("info", &format!("Fetching {}", repo.remote), Some(&repo.id));
    git_with_credential(
        repo,
        &["fetch", "--prune", &repo.remote],
        credential.as_ref(),
        paths,
    )?;
    logger.log("info", &format!("Fetched {}", repo.remote), Some(&repo.id));
    let upstream = format!("{}/{}", repo.remote, repo.branch);
    let (ahead, behind) = ahead_behind(repo, &upstream)?;

    if behind > 0 {
        logger.log("info", &format!("Merging {upstream}"), Some(&repo.id));
        let args = if ahead == 0 {
            vec!["merge", "--ff-only", upstream.as_str()]
        } else {
            vec!["merge", "--no-edit", upstream.as_str()]
        };
        let output = git_status(repo, &args)?;
        if !output.success() {
            if has_unmerged(repo)? {
                db.set_sync_failure(
                    &repo.id,
                    "needs_attention",
                    "merge conflicts require attention",
                )?;
                notify(
                    logger,
                    repo,
                    "needs_attention",
                    "Merge conflicts require attention",
                    true,
                );
                return Ok(SyncResult {
                    repository_id: repo.id.clone(),
                    status: "needs_attention".into(),
                    message: Some("Merge conflicts require attention".into()),
                    committed,
                    pushed: false,
                    skipped_binaries: skipped,
                    ahead,
                    behind,
                });
            }
            anyhow::bail!(
                "merge failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            );
        }
    }

    let (ahead, _behind) = ahead_behind(repo, &upstream)?;
    let mut pushed = false;
    if ahead > 0 {
        logger.log(
            "info",
            &format!("Pushing to {}", repo.remote),
            Some(&repo.id),
        );
        git_with_credential(
            repo,
            &["push", &repo.remote, &format!("HEAD:{}", repo.branch)],
            credential.as_ref(),
            paths,
        )?;
        pushed = true;
        logger.log("info", "Pushed local commits", Some(&repo.id));
    }
    let (ahead, behind) = ahead_behind(repo, &upstream).unwrap_or((0, 0));
    let status = if skipped.is_empty() {
        "idle"
    } else {
        "needs_attention"
    };
    db.set_sync_success(&repo.id, status, ahead, behind, &skipped)?;
    logger.log("info", "Synchronization completed", Some(&repo.id));
    Ok(SyncResult {
        repository_id: repo.id.clone(),
        status: status.into(),
        message: None,
        committed,
        pushed,
        skipped_binaries: skipped,
        ahead,
        behind,
    })
}

pub fn list_conflicts(repo: &Repository) -> Result<Vec<ConflictFile>> {
    let output = git(repo, &["diff", "--name-only", "--diff-filter=U", "-z"])?;
    output
        .split(|byte| *byte == 0)
        .filter(|path| !path.is_empty())
        .map(|path| {
            let path = String::from_utf8(path.to_vec())?;
            let base = stage(repo, 1, &path)?;
            let ours = stage(repo, 2, &path)?;
            let theirs = stage(repo, 3, &path)?;
            let result_bytes = std::fs::read(Path::new(&repo.worktree).join(&path)).ok();
            let binary = [&base, &ours, &theirs, &result_bytes]
                .into_iter()
                .flatten()
                .any(|v| v.iter().take(512).any(|b| *b == 0));
            Ok(ConflictFile {
                path,
                binary,
                base: text(base),
                ours: text(ours),
                theirs: text(theirs),
                result: text(result_bytes),
            })
        })
        .collect()
}

pub fn resolve_conflict(
    repo: &Repository,
    path: &str,
    choice: Option<&str>,
    content: Option<&str>,
) -> Result<()> {
    ensure_conflict_path(repo, path)?;
    let absolute = Path::new(&repo.worktree).join(path);
    if let Some(choice) = choice {
        match choice {
            "ours" => {
                git(repo, &["checkout", "--ours", "--", path])?;
            }
            "theirs" => {
                git(repo, &["checkout", "--theirs", "--", path])?;
            }
            _ => anyhow::bail!("choice must be ours or theirs"),
        }
    } else if let Some(content) = content {
        std::fs::write(&absolute, content)
            .with_context(|| format!("writing {}", absolute.display()))?;
    } else {
        anyhow::bail!("content or choice is required");
    }
    git(repo, &["add", "--", path])?;
    Ok(())
}

pub fn continue_merge(
    db: &Database,
    logger: &Logger,
    paths: &AppPaths,
    repo: &Repository,
) -> Result<()> {
    if has_unmerged(repo)? {
        anyhow::bail!("unresolved files remain");
    }
    git(repo, &["commit", "--no-edit"])?;
    let credential = repo
        .credential_id
        .as_deref()
        .map(|id| db.get_credential(id))
        .transpose()?;
    git_with_credential(
        repo,
        &["push", &repo.remote, &format!("HEAD:{}", repo.branch)],
        credential.as_ref(),
        paths,
    )?;
    db.set_sync_success(&repo.id, "idle", 0, 0, &[])?;
    logger.log("info", "Merge resolved and pushed", Some(&repo.id));
    Ok(())
}

pub fn abort_merge(repo: &Repository) -> Result<()> {
    git(repo, &["merge", "--abort"])?;
    Ok(())
}

pub fn recent_commits(repo: &Repository, limit: usize) -> Result<Vec<RecentCommit>> {
    let limit = limit.clamp(1, 50).to_string();
    let output = git(
        repo,
        &[
            "log",
            "-z",
            &format!("-n{limit}"),
            "--format=%H%x1f%h%x1f%an%x1f%aI%x1f%s",
        ],
    )?;
    output
        .split(|byte| *byte == 0)
        .filter(|record| !record.is_empty())
        .map(|record| {
            let value = String::from_utf8(record.to_vec())?;
            let mut fields = value.trim_start_matches('\n').splitn(5, '\u{1f}');
            Ok(RecentCommit {
                hash: fields.next().context("commit hash is missing")?.into(),
                short_hash: fields
                    .next()
                    .context("short commit hash is missing")?
                    .into(),
                author: fields.next().context("commit author is missing")?.into(),
                timestamp: fields.next().context("commit timestamp is missing")?.into(),
                subject: fields.next().context("commit subject is missing")?.into(),
            })
        })
        .collect()
}

fn status_paths(repo: &Repository) -> Result<Vec<String>> {
    let output = git(
        repo,
        &["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    )?;
    let chunks: Vec<&[u8]> = output
        .split(|byte| *byte == 0)
        .filter(|v| !v.is_empty())
        .collect();
    let mut paths = Vec::new();
    let mut index = 0;
    while index < chunks.len() {
        let chunk = chunks[index];
        if chunk.len() < 4 {
            anyhow::bail!("invalid Git status record");
        }
        let state = &chunk[..2];
        paths.push(String::from_utf8(chunk[3..].to_vec())?);
        index += if state == b"R " || state == b"C " || state == b" R" || state == b" C" {
            2
        } else {
            1
        };
    }
    paths.sort();
    paths.dedup();
    Ok(paths)
}

fn verify_repository(repo: &Repository) -> Result<()> {
    let actual = git(repo, &["rev-parse", "--absolute-git-dir"])?;
    let actual = std::fs::canonicalize(String::from_utf8(actual)?.trim())?;
    let expected = std::fs::canonicalize(&repo.git_dir)?;
    if actual != expected {
        anyhow::bail!("configured Git directory does not match worktree pointer");
    }
    Ok(())
}

fn ahead_behind(repo: &Repository, upstream: &str) -> Result<(i64, i64)> {
    let output = String::from_utf8(git(
        repo,
        &[
            "rev-list",
            "--left-right",
            "--count",
            &format!("HEAD...{upstream}"),
        ],
    )?)?;
    let mut values = output.split_whitespace();
    Ok((
        values.next().context("missing ahead count")?.parse()?,
        values.next().context("missing behind count")?.parse()?,
    ))
}

fn has_unmerged(repo: &Repository) -> Result<bool> {
    Ok(!git(repo, &["diff", "--name-only", "--diff-filter=U", "-z"])?.is_empty())
}
fn is_binary(path: &Path) -> Result<bool> {
    let mut file = File::open(path)?;
    let mut data = [0; 512];
    let len = file.read(&mut data)?;
    Ok(data[..len].contains(&0))
}
fn stage(repo: &Repository, number: u8, path: &str) -> Result<Option<Vec<u8>>> {
    let output = git_status(repo, &["show", &format!(":{number}:{path}")])?;
    Ok(output.success().then_some(output.stdout))
}
fn text(value: Option<Vec<u8>>) -> Option<String> {
    value.and_then(|v| String::from_utf8(v).ok())
}
fn ensure_conflict_path(repo: &Repository, path: &str) -> Result<()> {
    if list_conflicts(repo)?.iter().any(|f| f.path == path) {
        Ok(())
    } else {
        anyhow::bail!("path is not an active conflict")
    }
}

fn git(repo: &Repository, args: &[&str]) -> Result<Vec<u8>> {
    let output = git_status(repo, args)?;
    if !output.success() {
        anyhow::bail!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(output.stdout)
}

trait OutputStatus {
    fn success(&self) -> bool;
}
impl OutputStatus for Output {
    fn success(&self) -> bool {
        self.status.success()
    }
}

fn git_status(repo: &Repository, args: &[&str]) -> Result<Output> {
    let mut command = Command::new("git");
    command
        .args(args)
        .current_dir(&repo.worktree)
        .env("GIT_TERMINAL_PROMPT", "0");
    output_with_timeout(
        &mut command,
        Duration::from_secs(300),
        &format!("git {}", args.join(" ")),
    )
}

fn git_with_credential(
    repo: &Repository,
    args: &[&str],
    credential: Option<&crate::model::Credential>,
    paths: &AppPaths,
) -> Result<Vec<u8>> {
    let mut command = Command::new("git");
    command
        .args(args)
        .current_dir(&repo.worktree)
        .env("GIT_TERMINAL_PROMPT", "0")
        .env(
            "GIT_SSH_COMMAND",
            "ssh -o BatchMode=yes -o ConnectTimeout=20 -o ConnectionAttempts=2",
        );
    if let Some(credential) = credential {
        if credential.kind == "ssh" {
            let key = credential
                .private_key_path
                .as_deref()
                .context("SSH key path missing")?;
            let hosts = credential
                .known_hosts_path
                .as_deref()
                .context("known_hosts path missing")?;
            command.env("GIT_SSH_COMMAND", format!("ssh -o BatchMode=yes -o ConnectTimeout=20 -o ConnectionAttempts=2 -i '{}' -o IdentitiesOnly=yes -o UserKnownHostsFile='{}' -o StrictHostKeyChecking=yes", shell_quote(key), shell_quote(hosts)));
        } else {
            let executable = std::env::current_exe()?;
            let script = paths.state_dir.join(format!("askpass-{}", credential.id));
            let body = format!(
                "#!/data/data/com.termux/files/usr/bin/sh\nexec '{}' askpass '{}' \"$1\"\n",
                shell_quote(&executable.to_string_lossy()),
                shell_quote(&credential.id)
            );
            std::fs::write(&script, body)?;
            crate::paths::set_mode(&script, 0o700)?;
            command
                .env("GIT_ASKPASS", script)
                .env("GIT_ASKPASS_REQUIRE", "force");
        }
    }
    let output = output_with_timeout(
        &mut command,
        Duration::from_secs(120),
        &format!("git {}", args.join(" ")),
    )?;
    if !output.success() {
        anyhow::bail!(
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr).trim()
        );
    }
    Ok(output.stdout)
}

fn output_with_timeout(
    command: &mut Command,
    timeout: Duration,
    description: &str,
) -> Result<Output> {
    use std::process::Stdio;

    #[cfg(unix)]
    {
        use std::os::unix::process::CommandExt;
        command.process_group(0);
    }

    let mut child = command
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .with_context(|| format!("starting {description}"))?;
    let mut stdout = child.stdout.take().context("capturing Git stdout")?;
    let mut stderr = child.stderr.take().context("capturing Git stderr")?;
    let stdout_reader = thread::spawn(move || {
        let mut data = Vec::new();
        let _ = stdout.read_to_end(&mut data);
        data
    });
    let stderr_reader = thread::spawn(move || {
        let mut data = Vec::new();
        let _ = stderr.read_to_end(&mut data);
        data
    });
    let started = Instant::now();
    let status = loop {
        if let Some(status) = child.try_wait()? {
            break status;
        }
        if started.elapsed() >= timeout {
            #[cfg(unix)]
            {
                unsafe extern "C" {
                    fn kill(process_group: i32, signal: i32) -> i32;
                }
                // The child is the leader of the process group configured
                // above. A negative PID kills Git and descendants such as SSH.
                let _ = unsafe { kill(-(child.id() as i32), 9) };
            }
            let _ = child.kill();
            let _ = child.wait();
            let _ = stdout_reader.join();
            let _ = stderr_reader.join();
            anyhow::bail!(
                "{description} timed out after {} seconds",
                timeout.as_secs()
            );
        }
        thread::sleep(Duration::from_millis(100));
    };
    let stdout = stdout_reader
        .join()
        .map_err(|_| anyhow::anyhow!("Git stdout reader panicked"))?;
    let stderr = stderr_reader
        .join()
        .map_err(|_| anyhow::anyhow!("Git stderr reader panicked"))?;
    Ok(Output {
        status,
        stdout,
        stderr,
    })
}

fn shell_quote(value: &str) -> String {
    value.replace('\'', "'\\''")
}

fn try_lock(file: &File) -> Result<bool> {
    #[cfg(unix)]
    {
        use std::os::fd::AsRawFd;
        unsafe extern "C" {
            fn flock(fd: i32, operation: i32) -> i32;
        }
        Ok(unsafe { flock(file.as_raw_fd(), 6) } == 0)
    }
    #[cfg(not(unix))]
    {
        let _ = file;
        Ok(true)
    }
}

fn is_notification_point(n: i64) -> bool {
    let mut point = 5;
    while point < n {
        point *= 4;
    }
    point == n
}
pub fn notification_companion_available() -> bool {
    #[cfg(target_os = "android")]
    {
        Command::new("/system/bin/pm")
            .args(["path", "com.termux.api"])
            .output()
            .is_ok_and(|output| output.status.success() && !output.stdout.is_empty())
    }
    #[cfg(not(target_os = "android"))]
    {
        true
    }
}

fn notify(logger: &Logger, repo: &Repository, status: &str, message: &str, critical: bool) {
    if !notification_companion_available() {
        logger.log(
            "error",
            "Android notification was not delivered: install and open the Termux:API companion app from the same source as Termux",
            Some(&repo.id),
        );
        return;
    }
    let id = format!("mantis-{}", &repo.id[..8.min(repo.id.len())]);
    let urgency = if critical { "high" } else { "default" };
    let mut command = Command::new("termux-notification");
    command.args([
        "--id",
        &id,
        "--title",
        &format!("Mantis: {}", repo.name),
        "--content",
        message,
        "--priority",
        urgency,
        "--action",
        &format!(
            "am start -a android.intent.action.VIEW -d http://127.0.0.1:47831/repos/{}",
            repo.id
        ),
    ]);
    // The Termux:API bridge can wait forever when its Android companion is
    // unavailable. Notifications are best-effort and must never retain a Git
    // lock or block a queued synchronization.
    match output_with_timeout(&mut command, Duration::from_secs(10), "termux-notification") {
        Ok(output) if output.status.success() => logger.log(
            "info",
            &format!("Android notification delivered for {status}"),
            Some(&repo.id),
        ),
        Ok(output) => logger.log(
            "error",
            &format!(
                "Android notification failed: {}",
                String::from_utf8_lossy(&output.stderr).trim()
            ),
            Some(&repo.id),
        ),
        Err(error) => logger.log(
            "error",
            &format!("Android notification was not delivered: {error:#}"),
            Some(&repo.id),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{db::Database, logging::Logger, model::CreateRepository};

    #[test]
    fn notification_points() {
        assert!(super::is_notification_point(5));
        assert!(super::is_notification_point(20));
        assert!(!super::is_notification_point(6));
    }

    #[tokio::test]
    async fn syncs_text_and_skips_binary() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let remote = temp.path().join("remote.git");
        let worktree = temp.path().join("worktree");
        command(temp.path(), &["init", "--bare", remote.to_str().unwrap()])?;
        command(
            temp.path(),
            &[
                "clone",
                remote.to_str().unwrap(),
                worktree.to_str().unwrap(),
            ],
        )?;
        command(
            &worktree,
            &["config", "user.email", "mantis@example.invalid"],
        )?;
        command(&worktree, &["config", "user.name", "Mantis Test"])?;
        command(&worktree, &["switch", "-c", "main"])?;
        std::fs::write(worktree.join("seed.txt"), "seed\n")?;
        command(&worktree, &["add", "seed.txt"])?;
        command(&worktree, &["commit", "-m", "seed"])?;
        command(&worktree, &["push", "-u", "origin", "main"])?;

        let data = temp.path().join("data");
        let state = temp.path().join("state");
        let paths = AppPaths {
            data_dir: data.clone(),
            state_dir: state.clone(),
            database: data.join("mantis.db"),
            log_file: state.join("mantis.jsonl"),
            lock_dir: state.join("locks"),
            credentials_dir: data.join("credentials"),
        };
        paths.ensure()?;
        let db = Database::open(&paths.database)?;
        let logger = Logger::new(paths.log_file.clone())?;
        let repo = db.create_repository(CreateRepository {
            name: "test".into(),
            worktree: worktree.to_string_lossy().into(),
            git_dir: None,
            remote: "origin".into(),
            branch: Some("main".into()),
            credential_id: None,
            enabled: true,
            clone_url: None,
        })?;
        std::fs::write(worktree.join("note.txt"), "hello\n")?;
        std::fs::write(worktree.join("image.bin"), [1, 0, 2])?;
        let result = sync_repository(&db, &logger, &paths, &repo).await?;
        assert!(result.committed);
        assert!(result.pushed);
        assert_eq!(result.skipped_binaries, vec!["image.bin"]);
        let commits = recent_commits(&repo, 2)?;
        assert_eq!(commits.len(), 2);
        assert_eq!(commits[0].author, "Mantis Test");
        assert!(commits[0].subject.starts_with("Auto-sync:"));
        assert_eq!(commits[1].subject, "seed");
        assert_eq!(
            String::from_utf8(command_output(
                temp.path(),
                &[
                    "--git-dir",
                    remote.to_str().unwrap(),
                    "show",
                    "main:note.txt"
                ]
            )?)?,
            "hello\n"
        );
        assert!(
            !command_status(
                temp.path(),
                &[
                    "--git-dir",
                    remote.to_str().unwrap(),
                    "cat-file",
                    "-e",
                    "main:image.bin"
                ]
            )?
            .success()
        );
        db.set_status(&repo.id, "syncing", Some("old error"))?;
        assert_eq!(db.recover_interrupted_syncs()?, 1);
        let recovered = db.get_repository(&repo.id)?;
        assert_eq!(recovered.status, "failed");
        assert!(
            recovered
                .last_error
                .as_deref()
                .unwrap_or_default()
                .contains("interrupted")
        );
        Ok(())
    }

    fn command(cwd: &Path, args: &[&str]) -> Result<()> {
        let output = Command::new("git").args(args).current_dir(cwd).output()?;
        if !output.status.success() {
            anyhow::bail!("git failed: {}", String::from_utf8_lossy(&output.stderr))
        }
        Ok(())
    }
    fn command_output(cwd: &Path, args: &[&str]) -> Result<Vec<u8>> {
        let output = Command::new("git").args(args).current_dir(cwd).output()?;
        if !output.status.success() {
            anyhow::bail!("git failed: {}", String::from_utf8_lossy(&output.stderr))
        }
        Ok(output.stdout)
    }
    fn command_status(cwd: &Path, args: &[&str]) -> Result<Output> {
        Ok(Command::new("git").args(args).current_dir(cwd).output()?)
    }
}
