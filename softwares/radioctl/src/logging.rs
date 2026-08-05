use std::{
    fs,
    path::{Path, PathBuf},
    process,
    time::{SystemTime, UNIX_EPOCH},
};

use tracing_appender::non_blocking::WorkerGuard;
use tracing_subscriber::{fmt, layer::SubscriberExt, util::SubscriberInitExt, EnvFilter};

use crate::{config::state_directory, error::AppError};

const MAX_RETAINED_LOGS: usize = 10;

pub struct LoggingGuard {
    _writer: WorkerGuard,
    pub path: PathBuf,
}

pub fn init(filter: &str, override_path: Option<&Path>) -> Result<LoggingGuard, AppError> {
    let path = override_path
        .map(Path::to_path_buf)
        .unwrap_or_else(session_log_path);
    let directory = path.parent().unwrap_or_else(|| Path::new("."));
    fs::create_dir_all(directory).map_err(|source| AppError::Io {
        path: directory.to_path_buf(),
        source,
    })?;

    if override_path.is_none() {
        prune_logs(directory)?;
    }

    let filename = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("radioctl.log");
    let appender = tracing_appender::rolling::never(directory, filename);
    let (writer, guard) = tracing_appender::non_blocking(appender);
    let env_filter = EnvFilter::try_new(filter).unwrap_or_else(|_| EnvFilter::new("radioctl=info"));

    tracing_subscriber::registry()
        .with(env_filter)
        .with(fmt::layer().with_ansi(false).with_writer(writer))
        .try_init()
        .ok();

    Ok(LoggingGuard {
        _writer: guard,
        path,
    })
}

fn session_log_path() -> PathBuf {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs();
    state_directory()
        .join("logs")
        .join(format!("radioctl-{timestamp}-{}.log", process::id()))
}

fn prune_logs(directory: &Path) -> Result<(), AppError> {
    let mut logs = fs::read_dir(directory)
        .map_err(|source| AppError::Io {
            path: directory.to_path_buf(),
            source,
        })?
        .filter_map(Result::ok)
        .filter(|entry| {
            entry
                .file_name()
                .to_str()
                .is_some_and(|name| name.starts_with("radioctl-") && name.ends_with(".log"))
        })
        .collect::<Vec<_>>();
    logs.sort_by_key(|entry| entry.file_name());

    let remove_count = logs.len().saturating_sub(MAX_RETAINED_LOGS - 1);
    for entry in logs.into_iter().take(remove_count) {
        fs::remove_file(entry.path()).map_err(|source| AppError::Io {
            path: entry.path(),
            source,
        })?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_logs_do_not_share_a_fixed_name() {
        let path = session_log_path();
        let name = path.file_name().unwrap().to_string_lossy();
        assert!(name.contains(&process::id().to_string()));
        assert!(name.ends_with(".log"));
    }
}
