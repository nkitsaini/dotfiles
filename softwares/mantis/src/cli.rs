use crate::{db::Database, git, model::CreateRepository};
use anyhow::Result;
use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(
    name = "mantis",
    version,
    about = "Reliable Git synchronization for Termux"
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
