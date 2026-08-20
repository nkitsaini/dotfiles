use crate::{
    backup,
    db::Database,
    git,
    logging::Logger,
    model::{CreateRepository, UpdateBackupConfig},
};
use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "mantis",
    version,
    about = "Reliable Git synchronization and Restic backups for Termux"
)]
pub struct Cli {
    #[command(subcommand)]
    pub command: Command,
}

#[derive(Debug, Subcommand)]
pub enum Command {
    Serve {
        #[arg(long, default_value = "127.0.0.1:47831")]
        bind: String,
    },
    Sync {
        repository: String,
        #[arg(long, default_value_t = false)]
        wait: bool,
    },
    SyncAll {
        #[arg(long, default_value_t = false)]
        wait: bool,
    },
    Repo {
        #[command(subcommand)]
        command: RepoCommand,
    },
    Backup {
        #[command(subcommand)]
        command: BackupCommand,
    },
    AuthLink {
        #[arg(long, default_value = "http://127.0.0.1:47831")]
        base_url: String,
    },
    Status,
    ServiceHealth,
    #[command(hide = true)]
    Askpass {
        credential: String,
        prompt: String,
    },
}

#[derive(Debug, Subcommand)]
pub enum BackupCommand {
    Trigger,
    Init,
    Snapshots,
    Status,
    Prune,
    Check,
    Config {
        #[arg(long)]
        repository: Option<String>,
        #[arg(long)]
        password: Option<String>,
        #[arg(long)]
        hostname: Option<String>,
        #[arg(long)]
        paths: Option<Vec<String>>,
    },
}

pub fn run_backup_command(db: &Database, logger: &Logger, command: BackupCommand) -> Result<()> {
    match command {
        BackupCommand::Trigger => {
            let res = backup::run_backup(db, logger)?;
            println!("{}", serde_json::to_string_pretty(&res)?);
            if res.status == "failed" {
                anyhow::bail!(res.message.unwrap_or_else(|| "backup failed".into()));
            }
        }
        BackupCommand::Init => {
            let msg = backup::init_repository(db, logger)?;
            println!("{msg}");
        }
        BackupCommand::Snapshots => {
            let snaps = backup::list_snapshots(db)?;
            for s in snaps {
                println!(
                    "{}\t{}\t{}\t{}",
                    s.short_id,
                    s.time,
                    s.hostname,
                    s.paths.join(", ")
                );
            }
        }
        BackupCommand::Status => {
            let cfg = db.get_backup_config()?;
            println!("Status:\t\t{}", cfg.status);
            println!("Repository:\t{}", cfg.repository);
            println!("Hostname:\t{}", cfg.hostname);
            println!(
                "Last Attempt:\t{}",
                cfg.last_attempt.as_deref().unwrap_or("never")
            );
            println!(
                "Last Success:\t{}",
                cfg.last_success.as_deref().unwrap_or("never")
            );
            if let Some(err) = cfg.last_error {
                println!("Last Error:\t{}", err);
            }
            println!("Paths:\t\t{}", cfg.paths.join(", "));
        }
        BackupCommand::Prune => {
            let msg = backup::run_prune(db, logger)?;
            println!("{msg}");
        }
        BackupCommand::Check => {
            let msg = backup::run_check(db, logger)?;
            println!("{msg}");
        }
        BackupCommand::Config {
            repository,
            password,
            hostname,
            paths,
        } => {
            let updated = db.update_backup_config(UpdateBackupConfig {
                repository,
                password,
                hostname,
                paths,
                excludes: None,
                prune_opts: None,
                extra_options: None,
            })?;
            println!(
                "Backup configuration updated:\n{}",
                serde_json::to_string_pretty(&updated)?
            );
        }
    }
    Ok(())
}

#[derive(Debug, Subcommand)]
pub enum RepoCommand {
    Add {
        name: String,
        worktree: String,
        #[arg(long)]
        git_dir: Option<String>,
        #[arg(long, default_value = "origin")]
        remote: String,
        #[arg(long)]
        branch: Option<String>,
    },
    List,
    Remove {
        repository: String,
    },
}

pub fn run_repo_command(db: &Database, command: RepoCommand) -> Result<()> {
    match command {
        RepoCommand::Add {
            name,
            worktree,
            git_dir,
            remote,
            branch,
        } => {
            git::trust_worktree_ownership(&worktree)?;
            let repo = db.create_repository(CreateRepository {
                name,
                worktree,
                git_dir,
                remote,
                branch,
                credential_id: None,
                enabled: true,
                clone_url: None,
            })?;
            println!("{}", repo.id);
        }
        RepoCommand::List => {
            for repo in db.list_repositories()? {
                println!("{}\t{}\t{}", repo.id, repo.name, repo.worktree);
            }
        }
        RepoCommand::Remove { repository } => {
            let repo = db.find_repository(&repository)?;
            db.delete_repository(&repo.id)?;
        }
    }
    Ok(())
}

