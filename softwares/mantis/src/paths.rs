use anyhow::{Context, Result};
use std::path::PathBuf;

#[derive(Clone, Debug)]
pub struct AppPaths {
    pub data_dir: PathBuf,
    pub state_dir: PathBuf,
    pub database: PathBuf,
    pub log_file: PathBuf,
    pub lock_dir: PathBuf,
    pub credentials_dir: PathBuf,
}

impl AppPaths {
    pub fn discover() -> Result<Self> {
        let home = std::env::var_os("HOME").context("HOME is not set")?;
        let home = PathBuf::from(home);
        let data_dir = std::env::var_os("MANTIS_DATA_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                std::env::var_os("XDG_DATA_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| home.join(".local/share"))
                    .join("mantis")
            });
        let state_dir = std::env::var_os("MANTIS_STATE_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|| {
                std::env::var_os("XDG_STATE_HOME")
                    .map(PathBuf::from)
                    .unwrap_or_else(|| home.join(".local/state"))
                    .join("mantis")
            });
        Ok(Self {
            database: data_dir.join("mantis.db"),
            log_file: state_dir.join("mantis.jsonl"),
            lock_dir: state_dir.join("locks"),
            credentials_dir: data_dir.join("credentials"),
            data_dir,
            state_dir,
        })
    }

    pub fn ensure(&self) -> Result<()> {
        for directory in [
            &self.data_dir,
            &self.state_dir,
            &self.lock_dir,
            &self.credentials_dir,
        ] {
            std::fs::create_dir_all(directory)
                .with_context(|| format!("creating {}", directory.display()))?;
            set_mode(directory, 0o700)?;
        }
        Ok(())
    }
}

#[cfg(unix)]
pub fn set_mode(path: &std::path::Path, mode: u32) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    std::fs::set_permissions(path, std::fs::Permissions::from_mode(mode))?;
    Ok(())
}
