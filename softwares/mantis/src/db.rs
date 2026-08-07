use crate::model::{CreateCredential, CreateRepository, Credential, Repository};
use anyhow::{Context, Result};
use rusqlite::{Connection, OptionalExtension, Row, params};
use std::{
    path::Path,
    sync::{Arc, Mutex},
};
use uuid::Uuid;

#[derive(Clone)]
pub struct Database(Arc<Mutex<Connection>>);

impl Database {
    pub fn open(path: &Path) -> Result<Self> {
        let connection = Connection::open(path)?;
        connection.pragma_update(None, "journal_mode", "WAL")?;
        connection.pragma_update(None, "foreign_keys", "ON")?;
        connection.execute_batch(SCHEMA)?;
        crate::paths::set_mode(path, 0o600)?;
        Ok(Self(Arc::new(Mutex::new(connection))))
    }

    pub fn health(&self) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .query_row("SELECT 1", [], |_| Ok(()))?;
        Ok(())
    }

    pub fn recover_interrupted_syncs(&self) -> Result<usize> {
        Ok(self.0.lock().unwrap().execute(
            "UPDATE repositories SET status='failed',last_error='Synchronization was interrupted when the Mantis service stopped' WHERE status='syncing'",
            [],
        )?)
    }

    pub fn create_repository(&self, input: CreateRepository) -> Result<Repository> {
        let worktree = std::fs::canonicalize(&input.worktree)
            .with_context(|| format!("worktree does not exist: {}", input.worktree))?;
        let git_dir = match input.git_dir {
            Some(path) => std::fs::canonicalize(&path)
                .with_context(|| format!("git directory does not exist: {path}"))?,
            None => discover_git_dir(&worktree)?,
        };
        let branch = input
            .branch
            .unwrap_or_else(|| current_branch(&worktree).unwrap_or_else(|_| "main".into()));
        let id = Uuid::new_v4().to_string();
        self.0.lock().unwrap().execute(
            "INSERT INTO repositories (id,name,worktree,git_dir,remote,branch,credential_id,enabled) VALUES (?,?,?,?,?,?,?,?)",
            params![id, input.name, worktree.to_string_lossy(), git_dir.to_string_lossy(), input.remote, branch, input.credential_id, input.enabled],
        )?;
        self.get_repository(&id)
    }

    pub fn list_repositories(&self) -> Result<Vec<Repository>> {
        let connection = self.0.lock().unwrap();
        let mut statement = connection.prepare(REPO_SELECT)?;
        let values = statement
            .query_map([], row_repository)?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(values)
    }

    pub fn get_repository(&self, id: &str) -> Result<Repository> {
        self.0
            .lock()
            .unwrap()
            .query_row(&format!("{REPO_SELECT} WHERE id=?"), [id], row_repository)
            .with_context(|| format!("repository not found: {id}"))
    }

    pub fn find_repository(&self, id_or_name: &str) -> Result<Repository> {
        self.0
            .lock()
            .unwrap()
            .query_row(
                &format!("{REPO_SELECT} WHERE id=?1 OR name=?1"),
                [id_or_name],
                row_repository,
            )
            .with_context(|| format!("repository not found: {id_or_name}"))
    }

    pub fn delete_repository(&self, id: &str) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .execute("DELETE FROM repositories WHERE id=?", [id])?;
        Ok(())
    }

    pub fn set_sync_started(&self, id: &str) -> Result<()> {
        self.0.lock().unwrap().execute(
            "UPDATE repositories SET status='syncing',last_attempt=datetime('now'),last_error=NULL WHERE id=?", [id])?;
        Ok(())
    }

    pub fn set_sync_success(
        &self,
        id: &str,
        status: &str,
        ahead: i64,
        behind: i64,
        skipped: &[String],
    ) -> Result<()> {
        self.0.lock().unwrap().execute(
            "UPDATE repositories SET status=?,last_success=datetime('now'),last_error=NULL,ahead=?,behind=?,consecutive_failures=0,skipped_binaries=? WHERE id=?",
            params![status, ahead, behind, serde_json::to_string(skipped)?, id],
        )?;
        Ok(())
    }

    pub fn set_sync_failure(&self, id: &str, status: &str, error: &str) -> Result<i64> {
        let connection = self.0.lock().unwrap();
        connection.execute(
            "UPDATE repositories SET status=?,last_error=?,consecutive_failures=consecutive_failures+1 WHERE id=?",
            params![status, error, id],
        )?;
        Ok(connection.query_row(
            "SELECT consecutive_failures FROM repositories WHERE id=?",
            [id],
            |r| r.get(0),
        )?)
    }

    pub fn set_status(&self, id: &str, status: &str, error: Option<&str>) -> Result<()> {
        self.0.lock().unwrap().execute(
            "UPDATE repositories SET status=?,last_error=? WHERE id=?",
            params![status, error, id],
        )?;
        Ok(())
    }

    pub fn create_credential(
        &self,
        value: CreateCredential,
        private_key_path: Option<String>,
        known_hosts_path: Option<String>,
    ) -> Result<Credential> {
        let id = Uuid::new_v4().to_string();
        self.0.lock().unwrap().execute(
            "INSERT INTO credentials(id,name,kind,username,secret,private_key_path,known_hosts_path) VALUES(?,?,?,?,?,?,?)",
            params![id, value.name, value.kind, value.username, value.secret, private_key_path, known_hosts_path],
        )?;
        self.get_credential(&id)
    }

    pub fn list_credentials(&self) -> Result<Vec<Credential>> {
        let connection = self.0.lock().unwrap();
        let mut statement = connection.prepare(CREDENTIAL_SELECT)?;
        Ok(statement
            .query_map([], row_credential)?
            .collect::<rusqlite::Result<Vec<_>>>()?)
    }

    pub fn get_credential(&self, id: &str) -> Result<Credential> {
        self.0
            .lock()
            .unwrap()
            .query_row(
                &format!("{CREDENTIAL_SELECT} WHERE id=?"),
                [id],
                row_credential,
            )
            .with_context(|| format!("credential not found: {id}"))
    }

    pub fn delete_credential(&self, id: &str) -> Result<()> {
        self.0
            .lock()
            .unwrap()
            .execute("DELETE FROM credentials WHERE id=?", [id])?;
        Ok(())
    }

    pub fn insert_claim(&self, hash: &str, expires: &str) -> Result<()> {
        self.0.lock().unwrap().execute(
            "INSERT INTO claims(token_hash,expires_at) VALUES(?,?)",
            params![hash, expires],
        )?;
        Ok(())
    }

    pub fn consume_claim(&self, hash: &str) -> Result<bool> {
        let connection = self.0.lock().unwrap();
        let changed = connection.execute(
            "UPDATE claims SET used_at=datetime('now') WHERE token_hash=? AND used_at IS NULL AND expires_at>datetime('now')", [hash])?;
        Ok(changed == 1)
    }

    pub fn insert_session(&self, hash: &str, expires: &str) -> Result<()> {
        self.0.lock().unwrap().execute(
            "INSERT INTO sessions(token_hash,expires_at) VALUES(?,?)",
            params![hash, expires],
        )?;
        Ok(())
    }

    pub fn valid_session(&self, hash: &str) -> bool {
        self.0.lock().unwrap().query_row(
            "SELECT 1 FROM sessions WHERE token_hash=? AND revoked_at IS NULL AND expires_at>datetime('now')", [hash], |_| Ok(()),
        ).optional().ok().flatten().is_some()
    }

    pub fn revoke_sessions(&self) -> Result<()> {
        self.0.lock().unwrap().execute(
            "UPDATE sessions SET revoked_at=datetime('now') WHERE revoked_at IS NULL",
            [],
        )?;
        Ok(())
    }
}

fn discover_git_dir(worktree: &Path) -> Result<std::path::PathBuf> {
    let output = std::process::Command::new("git")
        .args(["rev-parse", "--absolute-git-dir"])
        .current_dir(worktree)
        .output()?;
    if !output.status.success() {
        anyhow::bail!("not a Git repository: {}", worktree.display());
    }
    std::fs::canonicalize(String::from_utf8_lossy(&output.stdout).trim())
        .context("resolving Git directory")
}

fn current_branch(worktree: &Path) -> Result<String> {
    let output = std::process::Command::new("git")
        .args(["branch", "--show-current"])
        .current_dir(worktree)
        .output()?;
    if !output.status.success() {
        anyhow::bail!("cannot read current branch");
    }
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}

const REPO_SELECT: &str = "SELECT id,name,worktree,git_dir,remote,branch,credential_id,enabled,status,last_attempt,last_success,last_error,ahead,behind,consecutive_failures,skipped_binaries FROM repositories";
fn row_repository(row: &Row<'_>) -> rusqlite::Result<Repository> {
    Ok(Repository {
        id: row.get(0)?,
        name: row.get(1)?,
        worktree: row.get(2)?,
        git_dir: row.get(3)?,
        remote: row.get(4)?,
        branch: row.get(5)?,
        credential_id: row.get(6)?,
        enabled: row.get(7)?,
        status: row.get(8)?,
        last_attempt: row.get(9)?,
        last_success: row.get(10)?,
        last_error: row.get(11)?,
        ahead: row.get(12)?,
        behind: row.get(13)?,
        consecutive_failures: row.get(14)?,
        skipped_binaries: serde_json::from_str(&row.get::<_, String>(15)?).unwrap_or_default(),
    })
}

const CREDENTIAL_SELECT: &str =
    "SELECT id,name,kind,username,secret,private_key_path,known_hosts_path FROM credentials";
fn row_credential(row: &Row<'_>) -> rusqlite::Result<Credential> {
    Ok(Credential {
        id: row.get(0)?,
        name: row.get(1)?,
        kind: row.get(2)?,
        username: row.get(3)?,
        secret: row.get(4)?,
        private_key_path: row.get(5)?,
        known_hosts_path: row.get(6)?,
    })
}

const SCHEMA: &str = r#"
CREATE TABLE IF NOT EXISTS repositories(
 id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,worktree TEXT NOT NULL UNIQUE,git_dir TEXT NOT NULL,
 remote TEXT NOT NULL DEFAULT 'origin',branch TEXT NOT NULL,credential_id TEXT REFERENCES credentials(id),enabled INTEGER NOT NULL DEFAULT 1,
 status TEXT NOT NULL DEFAULT 'idle',last_attempt TEXT,last_success TEXT,last_error TEXT,ahead INTEGER NOT NULL DEFAULT 0,
 behind INTEGER NOT NULL DEFAULT 0,consecutive_failures INTEGER NOT NULL DEFAULT 0,skipped_binaries TEXT NOT NULL DEFAULT '[]'
);
CREATE TABLE IF NOT EXISTS credentials(
 id TEXT PRIMARY KEY,name TEXT NOT NULL UNIQUE,kind TEXT NOT NULL CHECK(kind IN ('ssh','https')),username TEXT,secret TEXT,
 private_key_path TEXT,known_hosts_path TEXT
);
CREATE TABLE IF NOT EXISTS claims(token_hash TEXT PRIMARY KEY,expires_at TEXT NOT NULL,used_at TEXT);
CREATE TABLE IF NOT EXISTS sessions(token_hash TEXT PRIMARY KEY,expires_at TEXT NOT NULL,created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,revoked_at TEXT);
"#;
