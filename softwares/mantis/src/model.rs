use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Repository {
    pub id: String,
    pub name: String,
    pub worktree: String,
    pub git_dir: String,
    pub remote: String,
    pub branch: String,
    pub credential_id: Option<String>,
    pub enabled: bool,
    pub status: String,
    pub last_attempt: Option<String>,
    pub last_success: Option<String>,
    pub last_error: Option<String>,
    pub ahead: i64,
    pub behind: i64,
    pub consecutive_failures: i64,
    pub skipped_binaries: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateRepository {
    pub name: String,
    pub worktree: String,
    #[serde(default)]
    pub git_dir: Option<String>,
    #[serde(default = "default_remote")]
    pub remote: String,
    #[serde(default)]
    pub branch: Option<String>,
    #[serde(default)]
    pub credential_id: Option<String>,
    #[serde(default = "default_true")]
    pub enabled: bool,
    #[serde(default)]
    pub clone_url: Option<String>,
}

fn default_remote() -> String {
    "origin".into()
}
fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Credential {
    pub id: String,
    pub name: String,
    pub kind: String,
    pub username: Option<String>,
    #[serde(skip_serializing)]
    pub secret: Option<String>,
    pub private_key_path: Option<String>,
    pub known_hosts_path: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct CreateCredential {
    pub name: String,
    pub kind: String,
    pub username: Option<String>,
    pub secret: Option<String>,
    pub private_key: Option<String>,
    #[serde(default)]
    pub generate: bool,
}

#[derive(Debug, Serialize)]
pub struct SyncResult {
    pub repository_id: String,
    pub status: String,
    pub message: Option<String>,
    pub committed: bool,
    pub pushed: bool,
    pub skipped_binaries: Vec<String>,
    pub ahead: i64,
    pub behind: i64,
}

#[derive(Debug, Serialize)]
pub struct ConflictFile {
    pub path: String,
    pub binary: bool,
    pub base: Option<String>,
    pub ours: Option<String>,
    pub theirs: Option<String>,
    pub result: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct RecentCommit {
    pub hash: String,
    pub short_hash: String,
    pub author: String,
    pub timestamp: String,
    pub subject: String,
}
