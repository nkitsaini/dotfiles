use crate::db::Database;
use anyhow::Result;
use axum::http::{HeaderMap, header::COOKIE};
use chrono::{Duration, Utc};
use rand::RngCore;
use sha2::{Digest, Sha256};

pub fn random_token() -> String {
    let mut bytes = [0u8; 32];
    rand::rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

pub fn hash_token(token: &str) -> String {
    hex::encode(Sha256::digest(token.as_bytes()))
}

pub fn create_claim_token(db: &Database) -> Result<String> {
    let token = random_token();
    db.insert_claim(
        &hash_token(&token),
        &(Utc::now() + Duration::minutes(15))
            .format("%Y-%m-%d %H:%M:%S")
            .to_string(),
    )?;
    Ok(token)
}

pub fn exchange_claim(db: &Database, token: &str) -> Result<Option<String>> {
    if !db.consume_claim(&hash_token(token))? {
        return Ok(None);
    }
    let session = random_token();
    db.insert_session(
        &hash_token(&session),
        &(Utc::now() + Duration::days(365))
            .format("%Y-%m-%d %H:%M:%S")
            .to_string(),
    )?;
    Ok(Some(session))
}

pub fn authenticated(db: &Database, headers: &HeaderMap) -> bool {
    headers
        .get(COOKIE)
        .and_then(|value| value.to_str().ok())
        .and_then(|cookies| {
            cookies
                .split(';')
                .map(str::trim)
                .find_map(|cookie| cookie.strip_prefix("mantis_session="))
        })
        .is_some_and(|token| db.valid_session(&hash_token(token)))
}
