use anyhow::{Context, Result};
use chrono::Utc;
use serde::Serialize;
use std::{
    fs::{File, OpenOptions},
    io::Write,
    path::PathBuf,
    sync::{Arc, Mutex},
};
use tokio::sync::broadcast;

const MAX_LOG_SIZE: u64 = 10 * 1024 * 1024;
const RETAINED_FILES: usize = 5;

#[derive(Clone)]
pub struct Logger {
    path: PathBuf,
    file: Arc<Mutex<File>>,
    events: broadcast::Sender<String>,
}

#[derive(Serialize)]
struct Record<'a> {
    timestamp: String,
    level: &'a str,
    message: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    repository_id: Option<&'a str>,
}

impl Logger {
    pub fn new(path: PathBuf) -> Result<Self> {
        let file = open(&path)?;
        let (events, _) = broadcast::channel(256);
        Ok(Self {
            path,
            file: Arc::new(Mutex::new(file)),
            events,
        })
    }

    pub fn log(&self, level: &str, message: &str, repository_id: Option<&str>) {
        let message = redact(message);
        let record = Record {
            timestamp: Utc::now().to_rfc3339(),
            level,
            message: &message,
            repository_id,
        };
        if let Ok(mut json) = serde_json::to_string(&record) {
            json.push('\n');
            if let Ok(mut file) = self.file.lock() {
                let _ = file.write_all(json.as_bytes());
                let _ = file.flush();
            }
            let _ = self.events.send(json);
            let _ = self.rotate_if_needed();
        }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<String> {
        self.events.subscribe()
    }

    pub fn tail(&self, max_lines: usize) -> Result<Vec<String>> {
        let content = std::fs::read_to_string(&self.path).unwrap_or_default();
        let lines: Vec<_> = content.lines().map(ToOwned::to_owned).collect();
        let start = lines.len().saturating_sub(max_lines.min(5000));
        Ok(lines[start..].to_vec())
    }

    fn rotate_if_needed(&self) -> Result<()> {
        if std::fs::metadata(&self.path)?.len() < MAX_LOG_SIZE {
            return Ok(());
        }
        let mut guard = self.file.lock().expect("log mutex poisoned");
        guard.flush()?;
        for index in (1..RETAINED_FILES).rev() {
            let from = self.path.with_extension(format!("jsonl.{index}"));
            let to = self.path.with_extension(format!("jsonl.{}", index + 1));
            if from.exists() {
                let _ = std::fs::rename(from, to);
            }
        }
        let first = self.path.with_extension("jsonl.1");
        std::fs::rename(&self.path, first)?;
        *guard = open(&self.path)?;
        Ok(())
    }
}

fn open(path: &PathBuf) -> Result<File> {
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .read(true)
        .open(path)
        .with_context(|| format!("opening log {}", path.display()))?;
    crate::paths::set_mode(path, 0o600)?;
    Ok(file)
}

fn redact(input: &str) -> String {
    let mut value = input.to_owned();
    for marker in ["token=", "password=", "secret="] {
        let mut offset = 0;
        loop {
            let lower = value.to_ascii_lowercase();
            let Some(position) = lower.get(offset..).and_then(|tail| tail.find(marker)) else {
                break;
            };
            let start = offset + position + marker.len();
            let end = value[start..]
                .find(['&', ' ', '\n', '\t'])
                .map(|v| start + v)
                .unwrap_or(value.len());
            value.replace_range(start..end, "[REDACTED]");
            offset = start + "[REDACTED]".len();
        }
    }
    value
}

#[cfg(test)]
mod tests {
    #[test]
    fn redacts_secrets() {
        assert_eq!(super::redact("x?token=abc&ok=1"), "x?token=[REDACTED]&ok=1");
    }
}
