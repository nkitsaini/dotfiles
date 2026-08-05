use std::{error::Error, time::Instant};

use clap::Parser;
use futures_util::StreamExt;
use radioctl::{
    app::{Application, Intent},
    cli::{Cli, Command},
    config::Settings,
    logging,
    terminal::TerminalSession,
    tui,
};
use tokio::time::{self, Duration, MissedTickBehavior};

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    let cli = Cli::parse();
    let settings = Settings::load(&cli)?;
    let logging_guard = logging::init(&settings.log_level, settings.log_file.as_deref())?;

    tracing::info!(
        backend = ?settings.backend,
        wifi_interface = ?settings.wifi_interface,
        bluetooth_adapter = ?settings.bluetooth_adapter,
        auto_scan = settings.auto_scan,
        log_path = %logging_guard.path.display(),
        "starting radioctl"
    );

    if let Some(Command::Diagnose { json }) = cli.command {
        print_diagnostics_placeholder(json, &logging_guard.path);
        return Ok(());
    }

    let mut terminal_session = TerminalSession::enter()?;
    let mut application = Application::new();
    let started = Instant::now();
    let mut input = crossterm::event::EventStream::new();
    let mut animation = time::interval(Duration::from_millis(100));
    animation.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut dirty = true;

    while !application.should_quit() {
        if dirty {
            terminal_session
                .terminal_mut()
                .draw(|frame| tui::draw(frame, &mut application))?;
            dirty = false;
        }

        tokio::select! {
            maybe_event = input.next() => {
                match maybe_event {
                    Some(Ok(event)) => {
                        if let Some(intent) = application.handle_terminal_event(event) {
                            handle_intent(&mut application, intent, elapsed_ms(started));
                        }
                        dirty = true;
                    }
                    Some(Err(error)) => {
                        tracing::error!(%error, "terminal input stream failed");
                        application.report_runtime_error(
                            "Terminal input failed",
                            error.to_string(),
                            elapsed_ms(started),
                        );
                        dirty = true;
                    }
                    None => application.request_quit(),
                }
            }
            _ = animation.tick() => {
                dirty = application.tick(elapsed_ms(started));
            }
            result = tokio::signal::ctrl_c() => {
                if let Err(error) = result {
                    tracing::warn!(%error, "failed to listen for Ctrl-C");
                }
                application.request_quit();
            }
        }
    }

    tracing::info!("radioctl stopped");
    Ok(())
}

fn handle_intent(application: &mut Application, intent: Intent, now_ms: u64) {
    match intent {
        Intent::Quit => application.request_quit(),
        Intent::OpenDiagnostics => application.report_runtime_error(
            "Diagnostics are not available yet",
            "Backend diagnostics will be connected in the backend implementation phase.",
            now_ms,
        ),
        intent => {
            tracing::debug!(
                ?intent,
                "backend intent queued before backend initialization"
            );
            application.report_backend_pending(intent, now_ms);
        }
    }
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis().try_into().unwrap_or(u64::MAX)
}

fn print_diagnostics_placeholder(json: bool, log_path: &std::path::Path) {
    if json {
        println!("{{\"status\":\"backend initialization pending\"}}");
    } else {
        println!("radioctl backend initialization pending");
        println!("log: {}", log_path.display());
    }
}
