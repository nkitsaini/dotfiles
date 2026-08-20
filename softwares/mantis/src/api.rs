use crate::{
    auth, backup,
    db::Database,
    git,
    logging::Logger,
    model::{
        BackupConfig, CreateCredential, CreateRepository, Repository, ResticSnapshot,
        UpdateBackupConfig,
    },
    paths::AppPaths,
};
use anyhow::{Context, Result};
use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Query, State},
    http::{HeaderMap, HeaderValue, Request, StatusCode, header},
    middleware::{self, Next},
    response::{IntoResponse, Redirect, Response, Sse},
    routing::{delete, get, post, put},
};
use rust_embed::RustEmbed;
use serde::Deserialize;
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    io::Read,
    net::SocketAddr,
    path::PathBuf,
    process::{Command, Stdio},
    sync::{Arc, Mutex},
};
use tokio_stream::{StreamExt, wrappers::BroadcastStream};

const BUILD_ID: &str = "20260820.1";

#[derive(Clone)]
struct AppState {
    db: Database,
    logger: Logger,
    paths: AppPaths,
    // Value is true when one additional run is pending behind the active run.
    syncs: Arc<Mutex<HashMap<String, bool>>>,
    backup_running: Arc<Mutex<bool>>,
}


#[derive(RustEmbed)]
#[folder = "web/build"]
struct Assets;

pub async fn serve(db: Database, logger: Logger, paths: AppPaths, bind: String) -> Result<()> {
    let recovered = db.recover_interrupted_syncs()?;
    if recovered > 0 {
        logger.log(
            "warning",
            &format!("Recovered {recovered} interrupted synchronization state(s)"),
            None,
        );
    }
    if !git::notification_companion_available() {
        logger.log(
            "warning",
            "Background notifications are unavailable: install and open the Termux:API Android companion app",
            None,
        );
    }
    let state = AppState {
        db,
        logger: logger.clone(),
        paths,
        syncs: Arc::new(Mutex::new(HashMap::new())),
        backup_running: Arc::new(Mutex::new(false)),
    };
    for repo in state.db.list_repositories()? {
        if let Err(error) = git::trust_worktree_ownership(&repo.worktree) {
            logger.log(
                "warning",
                &format!(
                    "Could not add {} to Git safe.directory: {error:#}",
                    repo.worktree
                ),
                Some(&repo.id),
            );
        }
    }
    let app = Router::new()
        .route("/health", get(health))
        .route("/auth/claim", get(claim))
        .route("/api/public/sync-all", post(public_sync_all))
        .route("/api/public/sync", post(public_sync_named))
        .route("/api/public/repos/{id}/sync", post(public_sync_repo))
        .route("/api/public/backup", post(public_backup))
        .route("/api/backup/config", get(get_backup_config).put(update_backup_config))
        .route("/api/backup/trigger", post(trigger_backup))
        .route("/api/backup/init", post(init_backup))
        .route("/api/backup/prune", post(prune_backup))
        .route("/api/backup/check", post(check_backup))
        .route("/api/backup/snapshots", get(get_backup_snapshots))
        .route("/api/repos", get(list_repos).post(create_repo))
        .route("/api/repos/{id}", get(get_repo).delete(remove_repo))
        .route("/api/repos/{id}/sync", post(sync_repo))
        .route("/api/repos/{id}/commits", get(recent_commits))
        .route("/api/repos/{id}/conflicts", get(conflicts))
        .route("/api/repos/{id}/conflicts/resolve", put(resolve_conflict))
        .route("/api/repos/{id}/merge/continue", post(continue_merge))
        .route("/api/repos/{id}/merge/abort", post(abort_merge))
        .route(
            "/api/credentials",
            get(list_credentials).post(create_credential),
        )
        .route("/api/credentials/{id}", delete(remove_credential))
        .route("/api/credentials/{id}/public-key", get(public_key))
        .route("/api/credentials/{id}/test-github", post(test_github_ssh))
        .route("/api/credentials/{id}/host-key/scan", post(scan_host_key))
        .route("/api/credentials/{id}/host-key", put(confirm_host_key))
        .route("/api/fs", get(browse))
        .route("/api/fs/directory", post(create_directory))
        .route("/api/files", get(list_files))
        .route("/api/files/directory", post(create_directory))
        .route("/api/files/download", get(download_file))
        .route("/api/files/upload", put(upload_file))
        .route("/api/logs", get(logs))
        .route("/api/events", get(events))
        .route("/api/sessions/revoke-all", post(revoke_sessions))
        .fallback(static_asset)
        .layer(middleware::from_fn_with_state(
            state.clone(),
            log_failed_requests,
        ))
        .with_state(state);
    let address: SocketAddr = bind.parse().context("invalid bind address")?;
    logger.log(
        "info",
        &format!(
            "Mantis v{} build {BUILD_ID} listening on http://{address}",
            env!("CARGO_PKG_VERSION")
        ),
        None,
    );
    let listener = tokio::net::TcpListener::bind(address).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn log_failed_requests(
    State(state): State<AppState>,
    request: Request<Body>,
    next: Next,
) -> Response {
    let method = request.method().clone();
    let path = request.uri().path().to_owned();
    let response = next.run(request).await;
    if response.status().is_success() || response.status().is_redirection() {
        return response;
    }

    let status = response.status();
    let (parts, body) = response.into_parts();
    match axum::body::to_bytes(body, usize::MAX).await {
        Ok(bytes) => {
            let detail = serde_json::from_slice::<Value>(&bytes)
                .ok()
                .and_then(|value| value["error"].as_str().map(ToOwned::to_owned))
                .unwrap_or_else(|| String::from_utf8_lossy(&bytes).trim().to_owned());
            let message = if detail.is_empty() {
                format!("Request failed: {method} {path} -> {status}")
            } else {
                format!("Request failed: {method} {path} -> {status}: {detail}")
            };
            state.logger.log("error", &message, None);
            Response::from_parts(parts, Body::from(bytes))
        }
        Err(error) => {
            state.logger.log(
                "error",
                &format!(
                    "Request failed: {method} {path} -> {status}; response body error: {error}"
                ),
                None,
            );
            Response::from_parts(parts, Body::empty())
        }
    }
}

async fn health(State(state): State<AppState>) -> ApiResult<impl IntoResponse> {
    state.db.health().map_err(ApiError::internal)?;
    Ok((
        [(header::CACHE_CONTROL, "no-store")],
        Json(json!({
            "status": "ok",
            "version": env!("CARGO_PKG_VERSION"),
            "build": BUILD_ID,
            "notifications_available": git::notification_companion_available(),
        })),
    ))
}

#[derive(Deserialize)]
struct ClaimQuery {
    token: String,
}
async fn claim(
    State(state): State<AppState>,
    Query(query): Query<ClaimQuery>,
) -> ApiResult<Response> {
    let Some(session) =
        auth::exchange_claim(&state.db, &query.token).map_err(ApiError::internal)?
    else {
        return Err(ApiError::new(
            StatusCode::UNAUTHORIZED,
            "invalid or expired login link",
        ));
    };
    let mut response = Redirect::to("/").into_response();
    response.headers_mut().insert(
        header::SET_COOKIE,
        HeaderValue::from_str(&format!(
            "mantis_session={session}; Path=/; HttpOnly; SameSite=Strict; Max-Age=31536000"
        ))
        .unwrap(),
    );
    Ok(response)
}

fn require_auth(state: &AppState, headers: &HeaderMap) -> ApiResult<()> {
    if auth::authenticated(&state.db, headers) {
        Ok(())
    } else {
        Err(ApiError::new(StatusCode::UNAUTHORIZED, "login required"))
    }
}

fn require_public_trigger(headers: &HeaderMap) -> ApiResult<()> {
    let valid_header = headers
        .get("x-mantis-trigger")
        .and_then(|v| v.to_str().ok())
        == Some("1");
    let valid_type = headers
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|v| v.starts_with("application/json"));
    if valid_header && valid_type {
        Ok(())
    } else {
        Err(ApiError::new(
            StatusCode::FORBIDDEN,
            "missing automation headers",
        ))
    }
}

async fn list_repos(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Vec<Repository>>> {
    require_auth(&state, &headers)?;
    Ok(Json(
        state.db.list_repositories().map_err(ApiError::internal)?,
    ))
}
async fn get_repo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<Json<Repository>> {
    require_auth(&state, &headers)?;
    Ok(Json(
        state.db.get_repository(&id).map_err(ApiError::not_found)?,
    ))
}

async fn create_repo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(mut input): Json<CreateRepository>,
) -> ApiResult<(StatusCode, Json<Repository>)> {
    require_auth(&state, &headers)?;
    input.worktree = expand_home_path(&input.worktree)
        .to_string_lossy()
        .into_owned();
    input.git_dir = input
        .git_dir
        .as_deref()
        .map(expand_home_path)
        .map(|path| path.to_string_lossy().into_owned());
    if let Some(url) = &input.clone_url {
        clone_repository(&state, &input, url).map_err(ApiError::bad_request)?;
    }
    git::trust_worktree_ownership(&input.worktree).map_err(ApiError::bad_request)?;
    let repo = state
        .db
        .create_repository(input)
        .map_err(ApiError::bad_request)?;
    state.logger.log(
        "info",
        &format!("Registered repository {}", repo.name),
        Some(&repo.id),
    );
    Ok((StatusCode::CREATED, Json(repo)))
}

async fn remove_repo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    state
        .db
        .delete_repository(&id)
        .map_err(ApiError::not_found)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn sync_repo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_auth(&state, &headers)?;
    enqueue(&state, &id).await
}
async fn public_sync_repo(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_public_trigger(&headers)?;
    enqueue(&state, &id).await
}

#[derive(Deserialize)]
struct PublicSyncQuery {
    repository: String,
}

async fn public_sync_named(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<PublicSyncQuery>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_public_trigger(&headers)?;
    let repo = state
        .db
        .find_repository(&query.repository)
        .map_err(ApiError::not_found)?;
    let disposition = enqueue_id(&state, repo.clone()).await;
    Ok((
        StatusCode::ACCEPTED,
        Json(json!({"disposition":disposition,"repository_id":repo.id})),
    ))
}
async fn public_sync_all(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_public_trigger(&headers)?;
    let repositories = state.db.list_repositories().map_err(ApiError::internal)?;
    let mut queued = Vec::new();
    for repo in repositories.into_iter().filter(|repo| repo.enabled) {
        let id = repo.id.clone();
        let disposition = enqueue_id(&state, repo).await;
        queued.push(json!({"repository_id":id,"disposition":disposition}));
    }
    Ok((StatusCode::ACCEPTED, Json(json!({"queued":queued}))))
}

async fn enqueue(state: &AppState, id: &str) -> ApiResult<(StatusCode, Json<Value>)> {
    let repo = state.db.get_repository(id).map_err(ApiError::not_found)?;
    let disposition = enqueue_id(state, repo).await;
    Ok((
        StatusCode::ACCEPTED,
        Json(json!({"disposition":disposition,"repository_id":id})),
    ))
}

async fn enqueue_id(state: &AppState, repo: Repository) -> &'static str {
    let disposition = {
        let mut syncs = state.syncs.lock().unwrap();
        register_sync_request(&mut syncs, &repo.id)
    };
    state.logger.log(
        "info",
        &format!("Sync request {disposition}"),
        Some(&repo.id),
    );
    if disposition != "started" {
        return disposition;
    }
    let state = state.clone();
    let id = repo.id.clone();
    tokio::spawn(async move {
        loop {
            let _ = git::sync_repository(&state.db, &state.logger, &state.paths, &repo).await;
            let run_again = {
                let mut syncs = state.syncs.lock().unwrap();
                finish_sync_run(&mut syncs, &id)
            };
            if !run_again {
                break;
            }
            state
                .logger
                .log("info", "Starting queued sync request", Some(&id));
        }
    });
    disposition
}

fn register_sync_request(syncs: &mut HashMap<String, bool>, id: &str) -> &'static str {
    match syncs.get_mut(id) {
        None => {
            syncs.insert(id.to_owned(), false);
            "started"
        }
        Some(pending) if !*pending => {
            *pending = true;
            "queued"
        }
        Some(_) => "debounced",
    }
}

fn finish_sync_run(syncs: &mut HashMap<String, bool>, id: &str) -> bool {
    if syncs.get(id).copied().unwrap_or(false) {
        syncs.insert(id.to_owned(), false);
        true
    } else {
        syncs.remove(id);
        false
    }
}

#[derive(Deserialize)]
struct CommitQuery {
    limit: Option<usize>,
}

async fn recent_commits(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Query(query): Query<CommitQuery>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let repo = state.db.get_repository(&id).map_err(ApiError::not_found)?;
    let commits = git::recent_commits(&repo, query.limit.unwrap_or(5).clamp(1, 50))
        .map_err(ApiError::bad_request)?;
    Ok(Json(json!(commits)))
}

async fn conflicts(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let repo = state.db.get_repository(&id).map_err(ApiError::not_found)?;
    let files = git::list_conflicts(&repo).map_err(ApiError::bad_request)?;
    Ok(Json(json!({"repository":repo,"files":files})))
}

#[derive(Deserialize)]
struct ResolveRequest {
    path: String,
    choice: Option<String>,
    content: Option<String>,
}
async fn resolve_conflict(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(body): Json<ResolveRequest>,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    let repo = state.db.get_repository(&id).map_err(ApiError::not_found)?;
    git::resolve_conflict(
        &repo,
        &body.path,
        body.choice.as_deref(),
        body.content.as_deref(),
    )
    .map_err(ApiError::bad_request)?;
    Ok(StatusCode::NO_CONTENT)
}
async fn continue_merge(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    let repo = state.db.get_repository(&id).map_err(ApiError::not_found)?;
    git::continue_merge(&state.db, &state.logger, &state.paths, &repo)
        .map_err(ApiError::bad_request)?;
    Ok(StatusCode::NO_CONTENT)
}
async fn abort_merge(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    let repo = state.db.get_repository(&id).map_err(ApiError::not_found)?;
    git::abort_merge(&repo).map_err(ApiError::bad_request)?;
    state
        .db
        .set_status(&id, "idle", None)
        .map_err(ApiError::internal)?;
    state.logger.log("info", "Merge aborted", Some(&repo.id));
    Ok(StatusCode::NO_CONTENT)
}

async fn list_credentials(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let credentials = state.db.list_credentials().map_err(ApiError::internal)?;
    Ok(Json(json!(credentials)))
}
async fn create_credential(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<CreateCredential>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_auth(&state, &headers)?;
    if input.kind != "ssh" && input.kind != "https" {
        return Err(ApiError::bad_request(
            "credential kind must be ssh or https",
        ));
    }
    let (key_path, hosts_path) = if input.kind == "ssh" {
        let id = uuid::Uuid::new_v4().to_string();
        let key = state.paths.credentials_dir.join(&id);
        let hosts = state
            .paths
            .credentials_dir
            .join(format!("{id}.known_hosts"));
        if input.generate {
            let output = Command::new("ssh-keygen")
                .args(["-q", "-t", "ed25519", "-N", "", "-f"])
                .arg(&key)
                .output()
                .map_err(ApiError::internal)?;
            if !output.status.success() {
                return Err(ApiError::bad_request(String::from_utf8_lossy(
                    &output.stderr,
                )));
            }
        } else {
            std::fs::write(
                &key,
                input
                    .private_key
                    .as_deref()
                    .context("private_key is required")
                    .map_err(ApiError::bad_request)?,
            )
            .map_err(ApiError::internal)?;
            crate::paths::set_mode(&key, 0o600).map_err(ApiError::internal)?;
            let public = Command::new("ssh-keygen")
                .args(["-y", "-P", "", "-f"])
                .arg(&key)
                .output()
                .map_err(ApiError::internal)?;
            if !public.status.success() {
                let _ = std::fs::remove_file(&key);
                return Err(ApiError::bad_request(
                    "private key is invalid or passphrase-protected",
                ));
            }
            std::fs::write(format!("{}.pub", key.display()), public.stdout)
                .map_err(ApiError::internal)?;
        }
        std::fs::write(&hosts, "").map_err(ApiError::internal)?;
        crate::paths::set_mode(&key, 0o600).map_err(ApiError::internal)?;
        crate::paths::set_mode(&hosts, 0o600).map_err(ApiError::internal)?;
        (
            Some(key.to_string_lossy().into_owned()),
            Some(hosts.to_string_lossy().into_owned()),
        )
    } else {
        (None, None)
    };
    let credential = state
        .db
        .create_credential(input, key_path, hosts_path)
        .map_err(ApiError::bad_request)?;
    Ok((StatusCode::CREATED, Json(json!(credential))))
}
async fn remove_credential(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    state
        .db
        .delete_credential(&id)
        .map_err(ApiError::bad_request)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn public_key(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let credential = state.db.get_credential(&id).map_err(ApiError::not_found)?;
    let path = credential
        .private_key_path
        .context("not an SSH credential")
        .map_err(ApiError::bad_request)?;
    let value = std::fs::read_to_string(format!("{path}.pub")).map_err(ApiError::internal)?;
    Ok(Json(json!({"public_key":value.trim()})))
}

async fn test_github_ssh(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let credential = state.db.get_credential(&id).map_err(ApiError::not_found)?;
    let key = credential
        .private_key_path
        .context("not an SSH credential")
        .map_err(ApiError::bad_request)?;
    let known_hosts = credential
        .known_hosts_path
        .context("not an SSH credential")
        .map_err(ApiError::bad_request)?;
    let output = Command::new("ssh")
        .args(["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15"])
        .arg("-i")
        .arg(key)
        .args(["-o", "IdentitiesOnly=yes", "-o"])
        .arg(format!("UserKnownHostsFile={known_hosts}"))
        .args(["-o", "StrictHostKeyChecking=yes", "git@github.com"])
        .output()
        .map_err(ApiError::internal)?;
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    // GitHub deliberately exits with status 1 after successful authentication
    // because it does not provide shell access.
    let authenticated = github_auth_succeeded(output.status.success(), &stdout, &stderr);
    Ok(Json(json!({
        "authenticated": authenticated,
        "exit_code": output.status.code(),
        "stdout": stdout,
        "stderr": stderr,
    })))
}

fn github_auth_succeeded(status_success: bool, stdout: &str, stderr: &str) -> bool {
    status_success
        || stdout.contains("successfully authenticated")
        || stderr.contains("successfully authenticated")
}

#[derive(Deserialize)]
struct HostRequest {
    host: String,
}
async fn scan_host_key(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(body): Json<HostRequest>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let credential = state.db.get_credential(&id).map_err(ApiError::not_found)?;
    if credential.kind != "ssh" {
        return Err(ApiError::bad_request("not an SSH credential"));
    }
    if body.host.is_empty()
        || !body
            .host
            .chars()
            .all(|character| character.is_ascii_alphanumeric() || ".:-[]".contains(character))
    {
        return Err(ApiError::bad_request("invalid SSH host"));
    }
    let output = Command::new("ssh-keyscan")
        .args(["-T", "10", &body.host])
        .output()
        .map_err(ApiError::internal)?;
    if !output.status.success() || output.stdout.is_empty() {
        return Err(ApiError::bad_request("could not obtain an SSH host key"));
    }
    let scanned = String::from_utf8(output.stdout).map_err(ApiError::internal)?;
    let mut fingerprints = Vec::new();
    let mut accepted_keys = Vec::new();
    for line in scanned.lines().filter(|line| !line.starts_with('#')) {
        let mut child = Command::new("ssh-keygen")
            .args(["-lf", "-"])
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .spawn()
            .map_err(ApiError::internal)?;
        use std::io::Write;
        child
            .stdin
            .as_mut()
            .expect("piped stdin")
            .write_all(line.as_bytes())
            .map_err(ApiError::internal)?;
        let value = child.wait_with_output().map_err(ApiError::internal)?;
        if value.status.success() {
            fingerprints.push(String::from_utf8_lossy(&value.stdout).trim().to_owned());
            accepted_keys.push(line);
        }
    }
    if accepted_keys.is_empty() {
        return Err(ApiError::bad_request(
            "ssh-keyscan returned no valid SSH host keys",
        ));
    }
    let keys = format!("{}\n", accepted_keys.join("\n"));
    Ok(Json(
        json!({"host":body.host,"keys":keys,"fingerprints":fingerprints}),
    ))
}

#[derive(Deserialize)]
struct ConfirmHostRequest {
    keys: String,
}
async fn confirm_host_key(
    State(state): State<AppState>,
    headers: HeaderMap,
    Path(id): Path<String>,
    Json(body): Json<ConfirmHostRequest>,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    let credential = state.db.get_credential(&id).map_err(ApiError::not_found)?;
    let path = credential
        .known_hosts_path
        .context("not an SSH credential")
        .map_err(ApiError::bad_request)?;
    if body.keys.trim().is_empty() {
        return Err(ApiError::bad_request("known_hosts data is empty"));
    }
    std::fs::write(&path, body.keys).map_err(ApiError::internal)?;
    crate::paths::set_mode(std::path::Path::new(&path), 0o600).map_err(ApiError::internal)?;
    Ok(StatusCode::NO_CONTENT)
}

#[derive(Deserialize)]
struct BrowseQuery {
    path: Option<String>,
}
async fn browse(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<BrowseQuery>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let path = query.path.map(PathBuf::from).unwrap_or_else(|| {
        std::env::var_os("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|| PathBuf::from("/"))
    });
    directory_listing(&path, true)
        .map(Json)
        .map_err(ApiError::bad_request)
}

async fn list_files(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<BrowseQuery>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let path = query
        .path
        .map(|path| expand_home_path(&path))
        .unwrap_or_else(|| {
            std::env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("/"))
        });
    directory_listing(&path, false)
        .map(Json)
        .map_err(ApiError::bad_request)
}

fn directory_listing(path: &std::path::Path, directories_only: bool) -> Result<Value> {
    let canonical = std::fs::canonicalize(path)?;
    let mut entries = Vec::new();
    for item in std::fs::read_dir(&canonical)? {
        let item = item?;
        // fs::metadata follows symlinks, unlike DirEntry::metadata. Termux's
        // ~/storage shortcuts are symlinked directories.
        let Ok(metadata) = std::fs::metadata(item.path()) else {
            continue;
        };
        if directories_only && !metadata.is_dir() {
            continue;
        }
        entries.push(json!({
            "name": item.file_name().to_string_lossy().into_owned(),
            "path": item.path().to_string_lossy().into_owned(),
            "directory": metadata.is_dir(),
            "size": metadata.is_file().then_some(metadata.len())
        }));
    }
    entries.sort_by(|a, b| {
        b["directory"]
            .as_bool()
            .cmp(&a["directory"].as_bool())
            .then_with(|| a["name"].as_str().cmp(&b["name"].as_str()))
    });
    Ok(json!({
        "path": canonical.to_string_lossy().into_owned(),
        "parent": canonical.parent().map(|path| path.to_string_lossy().into_owned()),
        "entries": entries
    }))
}

#[derive(Deserialize)]
struct CreateDirectoryRequest {
    parent: String,
    name: String,
}

async fn create_directory(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(body): Json<CreateDirectoryRequest>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_auth(&state, &headers)?;
    validate_entry_name(&body.name).map_err(ApiError::bad_request)?;
    let parent = expand_home_path(&body.parent);
    if !parent.is_dir() {
        return Err(ApiError::bad_request("parent is not a directory"));
    }
    let path = parent.join(&body.name);
    std::fs::create_dir(&path).map_err(ApiError::bad_request)?;
    state.logger.log(
        "info",
        &format!("Created directory {}", path.display()),
        None,
    );
    Ok((
        StatusCode::CREATED,
        Json(json!({"path":path.to_string_lossy()})),
    ))
}

#[derive(Deserialize)]
struct FilePathQuery {
    path: String,
    name: Option<String>,
}

async fn download_file(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<FilePathQuery>,
) -> ApiResult<Response> {
    require_auth(&state, &headers)?;
    let path = expand_home_path(&query.path);
    if !path.is_file() {
        return Err(ApiError::bad_request("download target is not a file"));
    }
    let data = std::fs::read(&path).map_err(ApiError::bad_request)?;
    let filename = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("download")
        .replace(['\"', '\r', '\n'], "_");
    Ok(Response::builder()
        .header(header::CONTENT_TYPE, "application/octet-stream")
        .header(
            header::CONTENT_DISPOSITION,
            format!("attachment; filename=\"{filename}\""),
        )
        .body(Body::from(data))
        .unwrap())
}

async fn upload_file(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<FilePathQuery>,
    body: Body,
) -> ApiResult<(StatusCode, Json<Value>)> {
    require_auth(&state, &headers)?;
    let name = query
        .name
        .as_deref()
        .context("upload file name is required")
        .map_err(ApiError::bad_request)?;
    validate_entry_name(name).map_err(ApiError::bad_request)?;
    let directory = expand_home_path(&query.path);
    if !directory.is_dir() {
        return Err(ApiError::bad_request(
            "upload destination is not a directory",
        ));
    }
    let data = axum::body::to_bytes(body, 512 * 1024 * 1024)
        .await
        .map_err(ApiError::bad_request)?;
    let path = directory.join(name);
    std::fs::write(&path, &data).map_err(ApiError::bad_request)?;
    state.logger.log(
        "info",
        &format!("Uploaded {} ({} bytes)", path.display(), data.len()),
        None,
    );
    Ok((
        StatusCode::CREATED,
        Json(json!({"path":path.to_string_lossy(),"size":data.len()})),
    ))
}

fn validate_entry_name(name: &str) -> Result<()> {
    if name.is_empty() || name == "." || name == ".." || name.contains(['/', '\\', '\0']) {
        anyhow::bail!("name must be one filename or folder name");
    }
    Ok(())
}

#[derive(Deserialize)]
struct LogQuery {
    limit: Option<usize>,
}
async fn logs(
    State(state): State<AppState>,
    headers: HeaderMap,
    Query(query): Query<LogQuery>,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let lines = state
        .logger
        .tail(query.limit.unwrap_or(250))
        .map_err(ApiError::internal)?;
    let records: Vec<Value> = lines
        .into_iter()
        .filter_map(|line| serde_json::from_str(&line).ok())
        .collect();
    Ok(Json(json!(records)))
}
async fn events(State(state): State<AppState>, headers: HeaderMap) -> ApiResult<impl IntoResponse> {
    require_auth(&state, &headers)?;
    let stream = BroadcastStream::new(state.logger.subscribe())
        .filter_map(|event| event.ok())
        .map(|event| {
            Ok::<_, std::convert::Infallible>(
                axum::response::sse::Event::default()
                    .event("log")
                    .data(event),
            )
        });
    Ok(Sse::new(stream).keep_alive(axum::response::sse::KeepAlive::default()))
}
async fn revoke_sessions(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<StatusCode> {
    require_auth(&state, &headers)?;
    state.db.revoke_sessions().map_err(ApiError::internal)?;
    Ok(StatusCode::NO_CONTENT)
}

async fn static_asset(request: Request<Body>) -> Response {
    let requested = request.uri().path().trim_start_matches('/');
    let path = if requested.is_empty() {
        "index.html"
    } else {
        requested
    };
    let asset = Assets::get(path).or_else(|| Assets::get("index.html"));
    match asset {
        Some(asset) => Response::builder()
            .header(
                header::CONTENT_TYPE,
                mime_guess::from_path(path).first_or_octet_stream().as_ref(),
            )
            .body(Body::from(asset.data.into_owned()))
            .unwrap(),
        None => (StatusCode::NOT_FOUND, "frontend not built").into_response(),
    }
}

fn clone_repository(state: &AppState, input: &CreateRepository, url: &str) -> Result<()> {
    let worktree = PathBuf::from(&input.worktree);
    if let Some(parent) = worktree.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("creating content parent directory {}", parent.display()))?;
    }
    if let Some(git_dir) = &input.git_dir {
        let git_dir = PathBuf::from(git_dir);
        if let Some(parent) = git_dir.parent() {
            std::fs::create_dir_all(parent).with_context(|| {
                format!(
                    "creating detached Git parent directory {}",
                    parent.display()
                )
            })?;
        }
    }
    let mut command = Command::new("git");
    command.args(["clone", "--progress"]);
    if let Some(git_dir) = &input.git_dir {
        command.arg(format!("--separate-git-dir={git_dir}"));
    }
    command.env("GIT_TERMINAL_PROMPT", "0");
    if let Some(id) = &input.credential_id {
        let credential = state.db.get_credential(id)?;
        if credential.kind == "ssh" {
            let key = credential
                .private_key_path
                .context("SSH private key is missing")?;
            let hosts = credential
                .known_hosts_path
                .context("SSH known_hosts file is missing")?;
            command.env(
                "GIT_SSH_COMMAND",
                format!(
                    "ssh -i '{}' -o IdentitiesOnly=yes -o UserKnownHostsFile='{}' -o StrictHostKeyChecking=yes",
                    shell_quote(&key),
                    shell_quote(&hosts)
                ),
            );
        } else {
            let script = state
                .paths
                .state_dir
                .join(format!("askpass-{}", credential.id));
            let executable = std::env::current_exe()?;
            std::fs::write(
                &script,
                format!(
                    "#!/data/data/com.termux/files/usr/bin/sh\nexec '{}' askpass '{}' \"$1\"\n",
                    shell_quote(&executable.to_string_lossy()),
                    shell_quote(&credential.id)
                ),
            )?;
            crate::paths::set_mode(&script, 0o700)?;
            command
                .env("GIT_ASKPASS", script)
                .env("GIT_ASKPASS_REQUIRE", "force");
        }
    }
    state
        .logger
        .log("info", &format!("Clone: starting {}", input.name), None);
    let mut child = command
        .arg(url)
        .arg(&worktree)
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()?;
    let mut stderr = child
        .stderr
        .take()
        .context("capturing Git clone progress")?;
    let mut buffer = [0_u8; 1024];
    let mut pending = Vec::new();
    let mut full_stderr = Vec::new();
    loop {
        let count = stderr.read(&mut buffer)?;
        if count == 0 {
            break;
        }
        full_stderr.extend_from_slice(&buffer[..count]);
        for &byte in &buffer[..count] {
            if byte == b'\r' || byte == b'\n' {
                log_clone_progress(&state.logger, &mut pending);
            } else {
                pending.push(byte);
            }
        }
    }
    log_clone_progress(&state.logger, &mut pending);
    let status = child.wait()?;
    if !status.success() {
        state
            .logger
            .log("error", &format!("Clone: {} failed", input.name), None);
        anyhow::bail!(
            "clone failed: {}",
            String::from_utf8_lossy(&full_stderr).trim()
        );
    }
    state
        .logger
        .log("info", &format!("Clone: {} complete", input.name), None);
    Ok(())
}

fn expand_home_path(value: &str) -> PathBuf {
    let Some(home) = std::env::var_os("HOME").map(PathBuf::from) else {
        return PathBuf::from(value);
    };
    if value == "~" {
        home
    } else if let Some(relative) = value.strip_prefix("~/") {
        home.join(relative)
    } else {
        PathBuf::from(value)
    }
}

fn log_clone_progress(logger: &Logger, pending: &mut Vec<u8>) {
    if !pending.is_empty() {
        let message = String::from_utf8_lossy(pending).trim().to_owned();
        if !message.is_empty() {
            logger.log("info", &format!("Clone: {message}"), None);
        }
        pending.clear();
    }
}

fn shell_quote(value: &str) -> String {
    value.replace('\'', "'\\''")
}

type ApiResult<T> = Result<T, ApiError>;
struct ApiError {
    status: StatusCode,
    message: String,
}
impl ApiError {
    fn new(status: StatusCode, message: impl ToString) -> Self {
        Self {
            status,
            message: message.to_string(),
        }
    }
    fn internal(error: impl std::fmt::Display) -> Self {
        Self::new(StatusCode::INTERNAL_SERVER_ERROR, error)
    }
    fn bad_request(error: impl std::fmt::Display) -> Self {
        Self::new(StatusCode::BAD_REQUEST, error)
    }
    fn not_found(error: impl std::fmt::Display) -> Self {
        Self::new(StatusCode::NOT_FOUND, error)
    }
}
impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.status, Json(json!({"error":self.message}))).into_response()
    }
}

async fn get_backup_config(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<BackupConfig>> {
    require_auth(&state, &headers)?;
    Ok(Json(
        state.db.get_backup_config().map_err(ApiError::internal)?,
    ))
}

async fn update_backup_config(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<UpdateBackupConfig>,
) -> ApiResult<Json<BackupConfig>> {
    require_auth(&state, &headers)?;
    Ok(Json(
        state
            .db
            .update_backup_config(input)
            .map_err(ApiError::bad_request)?,
    ))
}

async fn init_backup(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let msg = backup::init_repository(&state.db, &state.logger).map_err(ApiError::internal)?;
    Ok(Json(json!({ "status": "ok", "message": msg })))
}

async fn trigger_backup(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    spawn_backup(state);
    Ok(Json(json!({ "status": "started", "message": "Backup started in background." })))
}

async fn public_backup(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    require_public_trigger(&headers)?;
    spawn_backup(state);
    Ok(Json(json!({ "status": "accepted", "message": "Backup triggered via public API." })))
}

fn spawn_backup(state: AppState) {
    let mut running = state.backup_running.lock().unwrap();
    if *running {
        state
            .logger
            .log("info", "Backup is already running, skipping trigger.", None);
        return;
    }
    *running = true;
    drop(running);

    tokio::spawn(async move {
        let res = backup::run_backup(&state.db, &state.logger);
        let mut r = state.backup_running.lock().unwrap();
        *r = false;
        if let Err(e) = res {
            state
                .logger
                .log("error", &format!("Background backup failed: {e:#}"), None);
        }
    });
}

async fn prune_backup(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let res = backup::run_prune(&state.db, &state.logger).map_err(ApiError::internal)?;
    Ok(Json(json!({ "status": "ok", "summary": res })))
}

async fn check_backup(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    require_auth(&state, &headers)?;
    let res = backup::run_check(&state.db, &state.logger).map_err(ApiError::internal)?;
    Ok(Json(json!({ "status": "ok", "summary": res })))
}

async fn get_backup_snapshots(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<Json<Vec<ResticSnapshot>>> {
    require_auth(&state, &headers)?;
    Ok(Json(
        backup::list_snapshots(&state.db).map_err(ApiError::internal)?,
    ))
}

#[cfg(test)]
mod tests {
    use super::{
        directory_listing, expand_home_path, finish_sync_run, github_auth_succeeded,
        register_sync_request,
    };
    use std::collections::HashMap;

    #[test]
    fn sync_requests_keep_at_most_one_pending_run() {
        let mut syncs = HashMap::new();
        assert_eq!(register_sync_request(&mut syncs, "notes"), "started");
        assert_eq!(register_sync_request(&mut syncs, "notes"), "queued");
        assert_eq!(register_sync_request(&mut syncs, "notes"), "debounced");
        assert!(finish_sync_run(&mut syncs, "notes"));
        assert!(!finish_sync_run(&mut syncs, "notes"));
        assert!(!syncs.contains_key("notes"));
    }

    #[test]
    fn github_success_message_counts_despite_nonzero_ssh_exit() {
        assert!(github_auth_succeeded(
            false,
            "",
            "Hi example! You've successfully authenticated, but GitHub does not provide shell access."
        ));
        assert!(!github_auth_succeeded(
            false,
            "",
            "Permission denied (publickey)."
        ));
    }

    #[test]
    fn expands_tilde_paths_from_home() {
        if let Some(home) = std::env::var_os("HOME") {
            assert_eq!(
                expand_home_path("~/.repo"),
                std::path::PathBuf::from(home).join(".repo")
            );
        }
        assert_eq!(
            expand_home_path("/tmp/content"),
            std::path::PathBuf::from("/tmp/content")
        );
    }

    #[cfg(unix)]
    #[test]
    fn directory_listing_includes_symlinked_directories_as_strings() {
        use std::os::unix::fs::symlink;

        let temp = tempfile::tempdir().unwrap();
        let target = temp.path().join("camera-roll");
        std::fs::create_dir(&target).unwrap();
        symlink(&target, temp.path().join("dcim")).unwrap();

        let listing = directory_listing(temp.path(), true).unwrap();
        let linked = listing["entries"]
            .as_array()
            .unwrap()
            .iter()
            .find(|entry| entry["name"] == "dcim")
            .expect("symlinked directory should be listed");

        assert!(linked["name"].is_string());
        assert!(linked["path"].is_string());
        assert_eq!(linked["directory"], true);
    }
}
