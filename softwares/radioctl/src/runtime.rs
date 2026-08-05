use std::{
    collections::BTreeMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};

use tokio::sync::{broadcast, mpsc};

use crate::{
    app::Intent,
    backend::{
        bluez::BluezBackend, network_manager::NetworkManagerBackend, BackendAction, BackendCommand,
        BackendDiagnostics, RadioBackend,
    },
    cli::BackendChoice,
    config::Settings,
    domain::{
        AppEvent, AppState, BackendEvent, BackendHealth, BackendKind, BackendPayload, DesiredState,
        EntityId, ErrorCategory, Operation, OperationId, OperationPhase, UserFacingError,
    },
};

pub struct Runtime {
    backends: BTreeMap<BackendKind, Arc<dyn RadioBackend>>,
    updates_tx: mpsc::Sender<AppEvent>,
    updates_rx: mpsc::Receiver<AppEvent>,
    next_operation: AtomicU64,
}

impl Runtime {
    pub async fn start(settings: &Settings) -> Self {
        let (updates_tx, updates_rx) = mpsc::channel(512);
        let mut runtime = Self {
            backends: BTreeMap::new(),
            updates_tx,
            updates_rx,
            next_operation: AtomicU64::new(1),
        };
        let connection = match zbus::Connection::system().await {
            Ok(connection) => connection,
            Err(error) => {
                runtime.queue_health(
                    BackendKind::NetworkManager,
                    BackendHealth::Unavailable,
                    format!("could not connect to the system D-Bus: {error}"),
                );
                runtime.queue_health(
                    BackendKind::Bluez,
                    BackendHealth::Unavailable,
                    format!("could not connect to the system D-Bus: {error}"),
                );
                return runtime;
            }
        };

        match settings.backend {
            BackendChoice::Auto | BackendChoice::NetworkManager => {
                let backend =
                    NetworkManagerBackend::new(connection.clone(), settings.wifi_interface.clone())
                        .await;
                runtime.add_backend(backend).await;
            }
            BackendChoice::Iwd => runtime.queue_health(
                BackendKind::Iwd,
                BackendHealth::Unavailable,
                "the iwd backend has not been initialized".into(),
            ),
            BackendChoice::WpaNetworkd => runtime.queue_health(
                BackendKind::WpaNetworkd,
                BackendHealth::Unavailable,
                "the wpa_supplicant + networkd backend has not been initialized".into(),
            ),
            BackendChoice::ConnMan => runtime.queue_health(
                BackendKind::ConnMan,
                BackendHealth::Unavailable,
                "the ConnMan backend has not been initialized".into(),
            ),
        }

        let bluez = BluezBackend::new(connection, settings.bluetooth_adapter.clone()).await;
        runtime.add_backend(bluez).await;
        runtime
    }

    async fn add_backend<B>(&mut self, backend: Arc<B>)
    where
        B: RadioBackend + 'static,
    {
        let backend: Arc<dyn RadioBackend> = backend;
        let kind = backend.kind();
        let probe = backend.probe().await;
        let receiver = backend.subscribe();
        self.forward_backend_events(backend.clone(), receiver);
        self.backends.insert(kind, backend.clone());
        if probe.status != crate::backend::ProbeStatus::Available {
            self.queue_health(
                kind,
                BackendHealth::Unavailable,
                probe
                    .detail
                    .unwrap_or_else(|| format!("{kind} is not running")),
            );
            return;
        }

        // Subscribe before the initial snapshot. A signal that lands during the
        // snapshot will therefore be applied at a later revision rather than lost.
        match backend.snapshot().await {
            Ok(event) => {
                let _ = self.updates_tx.send(AppEvent::Backend(event)).await;
            }
            Err(error) => self.queue_health(kind, BackendHealth::Degraded, error.detail),
        }
    }

    fn forward_backend_events(
        &self,
        backend: Arc<dyn RadioBackend>,
        mut receiver: broadcast::Receiver<BackendEvent>,
    ) {
        let updates = self.updates_tx.clone();
        tokio::spawn(async move {
            loop {
                match receiver.recv().await {
                    Ok(event) => {
                        if updates.send(AppEvent::Backend(event)).await.is_err() {
                            return;
                        }
                    }
                    Err(broadcast::error::RecvError::Lagged(skipped)) => {
                        tracing::warn!(backend = %backend.kind(), skipped, "backend event consumer lagged; forcing authoritative snapshot");
                        match backend.snapshot().await {
                            Ok(event) => {
                                if updates.send(AppEvent::Backend(event)).await.is_err() {
                                    return;
                                }
                            }
                            Err(error) => {
                                tracing::error!(backend = %backend.kind(), %error, "recovery snapshot failed")
                            }
                        }
                    }
                    Err(broadcast::error::RecvError::Closed) => return,
                }
            }
        });
    }

    pub async fn next_event(&mut self) -> Option<AppEvent> {
        self.updates_rx.recv().await
    }

    pub fn dispatch(&self, intent: Intent, state: &AppState, now_ms: u64) {
        if let Intent::Cancel(operation_id) = intent {
            if let Some(operation) = state.operations.get(&operation_id) {
                if let Some(backend) = self.backends.get(&operation.backend).cloned() {
                    tokio::spawn(async move {
                        if let Err(error) = backend.cancel(operation_id).await {
                            tracing::warn!(%error, operation = operation_id.0, "backend could not cancel operation");
                        }
                    });
                }
            }
            return;
        }

        let Some((backend_kind, target, desired, action, credential)) = route_intent(intent, state)
        else {
            return;
        };
        let id = OperationId(self.next_operation.fetch_add(1, Ordering::Relaxed));
        let backend_epoch = state
            .backends
            .get(&backend_kind)
            .map_or(1, |backend| backend.epoch);
        let operation = Operation {
            id,
            backend: backend_kind,
            target: target.clone(),
            desired,
            phase: OperationPhase::Queued,
            started_at_ms: now_ms,
            deadline_ms: now_ms + timeout_ms(desired),
            backend_epoch,
        };
        let _ = self
            .updates_tx
            .try_send(AppEvent::OperationStarted(operation));

        let Some(backend) = self.backends.get(&backend_kind).cloned() else {
            let _ = self.updates_tx.try_send(AppEvent::OperationFailed {
                id,
                error: unavailable_error(backend_kind, target),
                timestamp_ms: now_ms,
            });
            return;
        };
        let updates = self.updates_tx.clone();
        tokio::spawn(async move {
            let immediate_success = matches!(action, BackendAction::Scan | BackendAction::StopScan);
            let command = BackendCommand {
                operation_id: id,
                target: target.clone(),
                desired,
                action,
                credential,
                remember_credential: true,
            };
            match backend.execute(command).await {
                Ok(_acceptance) if immediate_success => {
                    let _ = updates
                        .send(AppEvent::OperationSucceeded {
                            id,
                            message: "scan request accepted".into(),
                            timestamp_ms: super::backend::dbus::monotonic_ms(),
                        })
                        .await;
                }
                Ok(acceptance) => {
                    let _ = updates
                        .send(AppEvent::OperationProgress {
                            id,
                            phase: acceptance.phase,
                            timestamp_ms: super::backend::dbus::monotonic_ms(),
                        })
                        .await;
                }
                Err(error) => {
                    let _ = updates
                        .send(AppEvent::OperationFailed {
                            id,
                            error: error.into_user_error(backend_kind, Some(target)),
                            timestamp_ms: super::backend::dbus::monotonic_ms(),
                        })
                        .await;
                }
            }
        });
    }

    pub async fn diagnostics(&self) -> Vec<BackendDiagnostics> {
        let mut diagnostics = Vec::with_capacity(self.backends.len());
        for backend in self.backends.values() {
            diagnostics.push(backend.diagnostics().await);
        }
        diagnostics
    }

    fn queue_health(&self, backend: BackendKind, health: BackendHealth, detail: String) {
        let _ = self.updates_tx.try_send(AppEvent::Backend(BackendEvent {
            backend,
            epoch: 1,
            revision: 1,
            observed_at_ms: super::backend::dbus::monotonic_ms(),
            payload: BackendPayload::Health {
                health,
                detail: Some(detail),
            },
        }));
    }
}

fn route_intent(
    intent: Intent,
    state: &AppState,
) -> Option<(
    BackendKind,
    EntityId,
    DesiredState,
    BackendAction,
    Option<crate::backend::Secret>,
)> {
    match intent {
        Intent::SetConnection {
            target,
            desired,
            credential,
        } => {
            let backend = backend_for_target(&target, state)?;
            let action = if desired == DesiredState::Connected {
                BackendAction::Connect
            } else {
                BackendAction::Disconnect
            };
            Some((backend, target, desired, action, credential))
        }
        Intent::ScanWifi => {
            let interface = state.wifi.selected_interface.as_ref()?;
            let info = state.wifi.interfaces.get(interface)?;
            Some((
                info.backend,
                EntityId::WifiInterface(interface.clone()),
                DesiredState::Scanning,
                BackendAction::Scan,
                None,
            ))
        }
        Intent::ToggleBluetoothDiscovery => {
            let adapter = state.bluetooth.selected_adapter.as_ref()?;
            let info = state.bluetooth.adapters.get(adapter)?;
            let (desired, action) = if info.scanning {
                (DesiredState::Idle, BackendAction::StopScan)
            } else {
                (DesiredState::Scanning, BackendAction::Scan)
            };
            Some((
                BackendKind::Bluez,
                EntityId::BluetoothAdapter(adapter.clone()),
                desired,
                action,
                None,
            ))
        }
        Intent::ToggleWifiRadio => {
            let interface = state.wifi.selected_interface.as_ref()?;
            let info = state.wifi.interfaces.get(interface)?;
            let powered = !info.powered;
            Some((
                info.backend,
                EntityId::WifiInterface(interface.clone()),
                if powered {
                    DesiredState::Powered
                } else {
                    DesiredState::Unpowered
                },
                BackendAction::SetPowered(powered),
                None,
            ))
        }
        Intent::ToggleBluetoothRadio => {
            let adapter = state.bluetooth.selected_adapter.as_ref()?;
            let info = state.bluetooth.adapters.get(adapter)?;
            let powered = !info.powered;
            Some((
                BackendKind::Bluez,
                EntityId::BluetoothAdapter(adapter.clone()),
                if powered {
                    DesiredState::Powered
                } else {
                    DesiredState::Unpowered
                },
                BackendAction::SetPowered(powered),
                None,
            ))
        }
        Intent::Quit | Intent::Cancel(_) | Intent::OpenDiagnostics => None,
    }
}

fn backend_for_target(target: &EntityId, state: &AppState) -> Option<BackendKind> {
    match target {
        EntityId::Wifi(id) => state
            .wifi
            .interfaces
            .get(&id.interface)
            .map(|interface| interface.backend),
        EntityId::WifiInterface(id) => state
            .wifi
            .interfaces
            .get(id)
            .map(|interface| interface.backend),
        EntityId::Bluetooth(_) | EntityId::BluetoothAdapter(_) => Some(BackendKind::Bluez),
    }
}

fn timeout_ms(desired: DesiredState) -> u64 {
    match desired {
        DesiredState::Connected => 45_000,
        DesiredState::Scanning => 20_000,
        _ => 15_000,
    }
}

fn unavailable_error(backend: BackendKind, target: EntityId) -> UserFacingError {
    UserFacingError {
        category: ErrorCategory::ServiceUnavailable,
        summary: format!("{backend} is not available"),
        detail: "The selected backend has no active D-Bus owner".into(),
        recovery: vec![
            format!("Start {backend}, then retry"),
            "Open diagnostics for ownership details".into(),
        ],
        retryable: true,
        backend: Some(backend),
        target: Some(target),
        raw_code: Some("backend-unavailable".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::domain::{
        Connectivity, InterfaceId, Ssid, WifiInterface, WifiNetwork, WifiNetworkId, WifiSecurity,
    };

    #[test]
    fn connected_intent_routes_to_the_interface_owner() {
        let interface = InterfaceId("wlan0".into());
        let id = WifiNetworkId {
            interface: interface.clone(),
            ssid: Ssid(b"home".to_vec()),
            security: WifiSecurity::Personal,
        };
        let mut state = AppState::default();
        state.wifi.interfaces.insert(
            interface.clone(),
            WifiInterface {
                id: interface,
                backend: BackendKind::Iwd,
                powered: true,
                scanning: false,
                last_scan_ms: None,
                capabilities: BTreeMap::new(),
            },
        );
        state.wifi.networks.insert(
            id.clone(),
            WifiNetwork {
                id: id.clone(),
                display_name: "home".into(),
                signal: 50,
                state: crate::domain::ConnectionState::Disconnected,
                connectivity: Connectivity::Unknown,
                saved: false,
                auto_join: false,
                bss_count: 1,
                active_bssid: None,
                present: true,
                last_seen_ms: 0,
            },
        );
        let routed = route_intent(
            Intent::SetConnection {
                target: EntityId::Wifi(id),
                desired: DesiredState::Connected,
                credential: None,
            },
            &state,
        )
        .unwrap();
        assert_eq!(routed.0, BackendKind::Iwd);
        assert_eq!(routed.3, BackendAction::Connect);
    }
}
