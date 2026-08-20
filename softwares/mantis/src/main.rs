mod api;
mod auth;
mod backup;
mod cli;
mod db;
mod git;
mod logging;
mod model;
mod paths;

use anyhow::Result;
use clap::Parser;
use cli::{Cli, Command};

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let paths = paths::AppPaths::discover()?;
    paths.ensure()?;
    let logger = logging::Logger::new(paths.log_file.clone())?;
    let db = db::Database::open(&paths.database)?;

    match cli.command {
        Command::Serve { bind } => api::serve(db, logger, paths, bind).await,
        Command::Sync {
            repository,
            wait: _,
        } => {
            let repo = db.find_repository(&repository)?;
            let result = git::sync_repository(&db, &logger, &paths, &repo).await;
            print_sync_result(result)
        }
        Command::SyncAll { wait: _ } => {
            let mut failed = false;
            for repo in db.list_repositories()? {
                if !repo.enabled {
                    continue;
                }
                if let Err(error) = git::sync_repository(&db, &logger, &paths, &repo).await {
                    eprintln!("{}: {error:#}", repo.name);
                    failed = true;
                }
            }
            if failed {
                anyhow::bail!("one or more repositories failed to synchronize");
            }
            Ok(())
        }
        Command::Repo { command } => cli::run_repo_command(&db, command),
        Command::Backup { command } => cli::run_backup_command(&db, &logger, command),
        Command::AuthLink { base_url } => {
            let token = auth::create_claim_token(&db)?;
            println!("{base_url}/auth/claim?token={token}");
            Ok(())
        }
        Command::Status => {
            for repo in db.list_repositories()? {
                println!(
                    "{}\t{}\t{}",
                    repo.name,
                    repo.status,
                    repo.last_success.as_deref().unwrap_or("never")
                );
            }
            Ok(())
        }
        Command::ServiceHealth => {
            db.health()?;
            println!("ok");
            Ok(())
        }
        Command::Askpass { credential, prompt } => {
            let credential = db.get_credential(&credential)?;
            if prompt.to_ascii_lowercase().contains("username") {
                println!("{}", credential.username.unwrap_or_default());
            } else {
                println!("{}", credential.secret.unwrap_or_default());
            }
            Ok(())
        }
    }
}

fn print_sync_result(result: Result<model::SyncResult>) -> Result<()> {
    let result = result?;
    println!("{}", serde_json::to_string_pretty(&result)?);
    if result.status == "failed" || result.status == "needs_attention" {
        anyhow::bail!(result.message.unwrap_or_else(|| result.status.clone()));
    }
    Ok(())
}
