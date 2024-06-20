use std::{
    process::{Command, Stdio},
    str::FromStr,
};

use anyhow::bail;
use clap::Parser;

#[derive(Debug, PartialEq, Clone, Copy)]
enum Change {
    Percent(f64),
    Static(f64),
}

const MAX_VOLUME: f64 = 2.;

impl Change {
    fn apply(&self, existing_value: f64) -> f64 {
        match self {
            Self::Percent(v) => existing_value * v / 100.,
            Self::Static(v) => existing_value + v,
        }
    }
}

impl FromStr for Change {
    type Err = anyhow::Error;
    fn from_str(s: &str) -> Result<Self, Self::Err> {
        let pat = regex::Regex::new(r#"^(?<value>[+-](\d|\.)+)(?<percent>%?)$"#).unwrap();
        let capture = match pat.captures(s) {
            Some(x) => x,
            None => bail!("Can't parse the change: {s}"),
        };
        let is_percent = &capture["percent"] != "";
        let value = f64::from_str(&capture["value"])?;

        if is_percent {
            Ok(Change::Percent(value))
        } else {
            Ok(Change::Static(value))
        }
    }
}

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Cli {
    /// Optional name to operate on
    #[arg(value_parser = clap::value_parser!(Change))]
    volume_change: Change,

    /// Sets a custom config file
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_change_parse() {
        assert_eq!(Change::from_str("+5").unwrap(), Change::Static(5.));
        assert_eq!(Change::from_str("+5%").unwrap(), Change::Percent(5.));
        assert_eq!(Change::from_str("+0.001%").unwrap(), Change::Percent(0.001));
        assert_eq!(Change::from_str("-5").unwrap(), Change::Static(-5.));
        assert_eq!(Change::from_str("-5%").unwrap(), Change::Percent(-5.));
        assert_eq!(
            Change::from_str("-0.001%").unwrap(),
            Change::Percent(-0.001)
        );
        assert!(Change::from_str("0.001").is_err());
        assert!(Change::from_str("0.001%").is_err());
        assert!(Change::from_str("x001%").is_err());
    }
}
