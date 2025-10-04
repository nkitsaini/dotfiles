use std::str::FromStr;

use anyhow::bail;

#[derive(Debug, PartialEq, Clone, Copy)]
pub enum Change {
    Percent(f64),
    Static(f64),
}

impl Change {
    pub fn apply_to(&self, existing_value: f64) -> f64 {
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
