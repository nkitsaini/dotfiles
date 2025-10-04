use std::{
    process::{Command, Stdio},
    str::FromStr,
};

use anyhow::bail;
use change::Change;
use clap::Parser;
mod change;

const MAX_VOLUME: f64 = 2.0;

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// change in volume (1 means full). like: "+0.5", "-0.5", "+0.5%", "-0.01%"
    #[arg(value_parser = clap::value_parser!(Change))]
    volume_change: Change,

    /// Set the sink name, default sink by wireplumber is used otherwise
    #[arg(short, long, default_value = "@DEFAULT_AUDIO_SINK@")]
    sink: String,
}

fn set_volume(sink: &str, value: f64) -> anyhow::Result<()> {
    let result = Command::new("wpctl")
        .arg("set-volume")
        .arg(sink)
        .arg(value.to_string())
        .status()?;
    if !result.success() {
        bail!("Setting volume failed with status code: {result}")
    }
    return Ok(());
}

fn get_volume(sink: &str) -> anyhow::Result<f64> {
    let result = Command::new("wpctl")
        .arg("get-volume")
        .arg(sink)
        .stderr(Stdio::inherit())
        .output()?;
    let result = String::from_utf8(result.stdout)?;
    assert!(result.contains("Volume: "));
    let result = f64::from_str(result.replace("Volume: ", "").trim())?;
    return Ok(result);
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();
    println!("Parsed: {:?}", cli.volume_change);

    let current_volume = get_volume(&cli.sink)?;
    println!("> Current volume: {current_volume}");

    let mut new_volume = cli
        .volume_change
        .apply(current_volume)
        .min(MAX_VOLUME)
        .max(0.);

    new_volume = (new_volume * 100.).round() / 100.;

    println!("> Setting new volume: {new_volume}");
    set_volume(&cli.sink, new_volume)?;
    println!("> Done");
    Ok(())
}
