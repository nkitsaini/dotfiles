use std::{error::Error, time::Instant};

use clap::Parser;
use futures_util::StreamExt;
use radioctl::{
    app::{Application, Intent},
    cli::{Cli, Command},
    config::Settings,
    logging,
    runtime::Runtime,
    terminal::{self, TerminalSession},
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

    let mut runtime = Runtime::start(&settings).await;
    if let Some(Command::Diagnose { json }) = cli.command {
        print_diagnostics(&runtime, json, &logging_guard.path).await?;
        return Ok(());
    }

    terminal::install_panic_hook();
    let mut terminal_session = TerminalSession::enter()?;
    let mut application = Application::new();
    let started = Instant::now();
    let mut input = crossterm::event::EventStream::new();
    let mut animation = time::interval(Duration::from_millis(100));
    animation.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut housekeeping = time::interval(Duration::from_secs(1));
    housekeeping.set_missed_tick_behavior(MissedTickBehavior::Skip);
    let mut dirty = true;
    let mut auto_scan_pending = settings.auto_scan;

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
                            handle_intent(&mut application, &runtime, intent, elapsed_ms(started)).await;
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
            event = runtime.next_event() => {
                if let Some(event) = event {
                    application.reducer.apply(event);
                    if auto_scan_pending
                        && application.reducer.state.wifi.selected_interface.is_some()
                    {
                        runtime.dispatch(
                            Intent::ScanWifi,
                            &application.reducer.state,
                            elapsed_ms(started),
                        );
                        auto_scan_pending = false;
                    }
                    dirty = true;
                }
            }
            _ = animation.tick(), if application.needs_animation() => {
                dirty = application.tick(elapsed_ms(started));
            }
            _ = housekeeping.tick() => {
                dirty |= application.tick(elapsed_ms(started));
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

async fn handle_intent(
    application: &mut Application,
    runtime: &Runtime,
    intent: Intent,
    now_ms: u64,
) {
    match intent {
        Intent::Quit => application.request_quit(),
        Intent::OpenDiagnostics => {
            let lines = runtime
                .diagnostics()
                .await
                .into_iter()
                .flat_map(|backend| {
                    let mut lines = vec![format!(
                        "{}: {}{}",
                        backend.backend,
                        backend.owner.as_deref().unwrap_or("not running"),
                        backend
                            .version
                            .as_ref()
                            .map_or_else(String::new, |version| format!(" ({version})"))
                    )];
                    lines.extend(
                        backend
                            .properties
                            .into_iter()
                            .map(|(name, value)| format!("  {name}: {value}")),
                    );
                    lines.extend(
                        backend
                            .warnings
                            .into_iter()
                            .map(|warning| format!("  warning: {warning}")),
                    );
                    lines.push(String::new());
                    lines
                })
                .collect();
            application.show_diagnostics(lines);
        }
        intent => runtime.dispatch(intent, &application.reducer.state, now_ms),
    }
}

fn elapsed_ms(started: Instant) -> u64 {
    started.elapsed().as_millis().try_into().unwrap_or(u64::MAX)
}

async fn print_diagnostics(
    runtime: &Runtime,
    json: bool,
    log_path: &std::path::Path,
) -> Result<(), Box<dyn Error>> {
    let diagnostics = runtime.diagnostics().await;
    if json {
        let backends = diagnostics
            .into_iter()
            .map(|backend| {
                serde_json::json!({
                    "backend": backend.backend.to_string(),
                    "available": backend.owner.is_some(),
                    "owner": backend.owner,
                    "version": backend.version,
                    "properties": backend.properties,
                    "warnings": backend.warnings,
                })
            })
            .collect::<Vec<_>>();
        println!(
            "{}",
            serde_json::to_string_pretty(&serde_json::json!({
                "log": log_path,
                "backends": backends,
            }))?
        );
    } else {
        println!("log: {}", log_path.display());
        for backend in diagnostics {
            println!();
            println!(
                "{}: {}",
                backend.backend,
                backend.owner.as_deref().unwrap_or("not running")
            );
            if let Some(version) = backend.version {
                println!("  version: {version}");
            }
            for (name, value) in backend.properties {
                println!("  {name}: {value}");
            }
            for warning in backend.warnings {
                println!("  warning: {warning}");
            }
        }
    }
    Ok(())
}
