use crate::{
    db::Database,
    logging::Logger,
    model::{BackupConfig, BackupResult, ResticSnapshot},
};
use anyhow::{Context, Result, bail};
use std::{
    path::{Path, PathBuf},
    process::{Command, Stdio},
};

pub fn find_restic() -> Result<PathBuf> {
    if let Some(paths) = std::env::var_os("PATH") {
        for dir in std::env::split_paths(&paths) {
            let p = dir.join("restic");
            if p.exists() && p.is_file() {
                return Ok(p);
            }
        }
    }
    let candidates = [
        "/data/data/com.termux/files/usr/bin/restic",
        "/usr/local/bin/restic",
        "/usr/bin/restic",
    ];
    for candidate in candidates {
        let p = Path::new(candidate);
        if p.exists() && p.is_file() {
            return Ok(p.to_path_buf());
        }
    }
    bail!("restic binary not found in PATH or standard directories")
}

fn build_restic_command(
    config: &BackupConfig,
    password: &str,
    subcommand: &str,
    extra_args: &[&str],
) -> Result<Command> {
    if config.repository.trim().is_empty() {
        bail!("Backup repository is not configured. Please set the repository in settings.");
    }
    let restic_bin = find_restic()?;
    let mut cmd = Command::new(restic_bin);
    cmd.env("RESTIC_REPOSITORY", config.repository.trim());
    cmd.env("RESTIC_PASSWORD", password.trim());
    
    // Pass extra options
    for opt in &config.extra_options {
        if !opt.trim().is_empty() {
            cmd.arg("-o").arg(opt.trim());
        }
    }
    
    cmd.arg(subcommand);
    cmd.args(extra_args);
    Ok(cmd)
}

pub fn init_repository(db: &Database, logger: &Logger) -> Result<String> {
    let (config, password) = db.get_backup_config_raw()?;
    logger.log("info", &format!("Initializing restic repository: {}", config.repository), None);

    let mut cmd = build_restic_command(&config, &password, "init", &[])?;
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    
    let output = cmd.output().context("failed to execute restic init")?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        // If already initialized, restic reports repository already exists
        if stderr.contains("already exists") || stdout.contains("already exists") {
            logger.log("info", "Restic repository is already initialized", None);
            return Ok("Repository is already initialized.".to_string());
        }
        let err_msg = if !stderr.is_empty() { stderr } else { stdout };
        logger.log("error", &format!("restic init failed: {err_msg}"), None);
        bail!("restic init failed: {err_msg}");
    }

    let msg = if !stdout.is_empty() { stdout } else { "Repository initialized successfully.".into() };
    logger.log("info", &format!("restic init success: {msg}"), None);
    Ok(msg)
}

pub fn run_backup(db: &Database, logger: &Logger) -> Result<BackupResult> {
    let (config, password) = db.get_backup_config_raw()?;
    if config.repository.trim().is_empty() {
        bail!("Backup repository is not configured.");
    }
    if config.paths.is_empty() {
        bail!("No backup paths specified.");
    }

    db.set_backup_started()?;
    logger.log("info", "Starting restic backup run...", None);

    let mut args: Vec<String> = Vec::new();
    let hostname = if config.hostname.trim().is_empty() {
        "mantis".to_string()
    } else {
        config.hostname.trim().to_string()
    };
    args.push("--host".into());
    args.push(hostname);

    for exclude in &config.excludes {
        if !exclude.trim().is_empty() {
            args.push("--exclude".into());
            args.push(exclude.trim().into());
        }
    }

    // Filter existing paths to avoid restic failing on non-existent directories
    let mut valid_paths = Vec::new();
    for p in &config.paths {
        let p_trimmed = p.trim();
        if !p_trimmed.is_empty() {
            if Path::new(p_trimmed).exists() {
                valid_paths.push(p_trimmed.to_string());
            } else {
                logger.log("warning", &format!("Backup path does not exist, skipping: {p_trimmed}"), None);
            }
        }
    }

    if valid_paths.is_empty() {
        let err = "None of the configured backup paths exist on this device.";
        db.set_backup_failure(err)?;
        logger.log("error", err, None);
        bail!("{err}");
    }

    for p in valid_paths {
        args.push(p);
    }

    let arg_refs: Vec<&str> = args.iter().map(|s| s.as_str()).collect();
    let mut cmd = match build_restic_command(&config, &password, "backup", &arg_refs) {
        Ok(c) => c,
        Err(e) => {
            db.set_backup_failure(&e.to_string())?;
            return Err(e);
        }
    };

    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let output = match cmd.output() {
        Ok(out) => out,
        Err(e) => {
            let msg = format!("Failed to run restic: {e}");
            db.set_backup_failure(&msg)?;
            logger.log("error", &msg, None);
            return Err(e).context("running restic backup");
        }
    };

    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        let err_msg = if !stderr.is_empty() { stderr } else { stdout };
        db.set_backup_failure(&err_msg)?;
        logger.log("error", &format!("Restic backup failed: {err_msg}"), None);
        return Ok(BackupResult {
            status: "failed".into(),
            message: Some(err_msg),
            summary: None,
        });
    }

    db.set_backup_success()?;
    logger.log("info", "Restic backup completed successfully.", None);
    Ok(BackupResult {
        status: "success".into(),
        message: Some("Backup completed successfully.".into()),
        summary: Some(stdout),
    })
}

pub fn run_prune(db: &Database, logger: &Logger) -> Result<String> {
    let (config, password) = db.get_backup_config_raw()?;
    logger.log("info", "Running restic forget --prune...", None);

    let mut args = vec!["--prune"];
    for opt in &config.prune_opts {
        if !opt.trim().is_empty() {
            args.push(opt.trim());
        }
    }

    let mut cmd = build_restic_command(&config, &password, "forget", &args)?;
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let output = cmd.output().context("failed to execute restic forget")?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        let err_msg = if !stderr.is_empty() { stderr } else { stdout };
        logger.log("error", &format!("restic forget failed: {err_msg}"), None);
        bail!("restic forget failed: {err_msg}");
    }

    logger.log("info", &format!("restic prune success: {stdout}"), None);
    Ok(stdout)
}

pub fn run_check(db: &Database, logger: &Logger) -> Result<String> {
    let (config, password) = db.get_backup_config_raw()?;
    logger.log("info", "Running restic check...", None);

    let mut cmd = build_restic_command(&config, &password, "check", &[])?;
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let output = cmd.output().context("failed to execute restic check")?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !output.status.success() {
        let err_msg = if !stderr.is_empty() { stderr } else { stdout };
        logger.log("error", &format!("restic check failed: {err_msg}"), None);
        bail!("restic check failed: {err_msg}");
    }

    logger.log("info", "Restic check verified repository integrity.", None);
    Ok(stdout)
}

pub fn list_snapshots(db: &Database) -> Result<Vec<ResticSnapshot>> {
    let (config, password) = db.get_backup_config_raw()?;
    let mut cmd = build_restic_command(&config, &password, "snapshots", &["--json"])?;
    cmd.stdout(Stdio::piped()).stderr(Stdio::piped());
    let output = cmd.output().context("failed to execute restic snapshots")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        bail!("failed to list snapshots: {stderr}");
    }

    let snapshots: Vec<ResticSnapshot> = serde_json::from_slice(&output.stdout)
        .context("parsing restic snapshots JSON")?;
    Ok(snapshots)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Database;
    use crate::model::UpdateBackupConfig;

    #[test]
    fn default_backup_config_initialization() {
        let temp = tempfile::tempdir().unwrap();
        let db_path = temp.path().join("mantis.db");
        let db = Database::open(&db_path).unwrap();

        let cfg = db.get_backup_config().unwrap();
        assert_eq!(cfg.hostname, "mantis");
        assert_eq!(cfg.status, "idle");
        assert!(!cfg.paths.is_empty());
        assert!(cfg.paths.contains(&"/sdcard/Download".to_string()));
        assert!(cfg.excludes.contains(&"*/.cache".to_string()));
    }

    #[test]
    fn update_backup_config_overrides() {
        let temp = tempfile::tempdir().unwrap();
        let db_path = temp.path().join("mantis.db");
        let db = Database::open(&db_path).unwrap();

        let updated = db
            .update_backup_config(UpdateBackupConfig {
                repository: Some("sftp:user@host:/backups".into()),
                password: Some("secret123".into()),
                hostname: Some("phone-custom".into()),
                paths: Some(vec!["/sdcard/DCIM".into()]),
                excludes: None,
                prune_opts: None,
                extra_options: None,
            })
            .unwrap();

        assert_eq!(updated.repository, "sftp:user@host:/backups");
        assert_eq!(updated.hostname, "phone-custom");
        assert_eq!(updated.paths, vec!["/sdcard/DCIM".to_string()]);
        assert!(updated.has_password);
        assert_eq!(updated.password, None); // Redacted on read

        let (_, raw_pwd) = db.get_backup_config_raw().unwrap();
        assert_eq!(raw_pwd, "secret123");
    }

    #[test]
    fn parses_restic_snapshots_json() {
        let sample_json = r#"[
            {
                "time": "2026-08-20T10:00:00Z",
                "tree": "abc123tree",
                "paths": ["/sdcard/Download", "/sdcard/Documents"],
                "hostname": "mantis",
                "username": "termux",
                "id": "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
                "short_id": "12345678"
            }
        ]"#;

        let snaps: Vec<ResticSnapshot> = serde_json::from_str(sample_json).unwrap();
        assert_eq!(snaps.len(), 1);
        assert_eq!(snaps[0].short_id, "12345678");
        assert_eq!(snaps[0].hostname, "mantis");
        assert_eq!(snaps[0].paths.len(), 2);
    }
}

