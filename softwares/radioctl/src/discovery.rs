use crate::{
    app::{Intent, Pane},
    domain::{
        AdapterId, AppEvent, AppState, BackendKind, BackendPayload, Capability, CapabilityState,
        ConnectionState, EntityId, OperationId,
    },
};

const WIFI_FOREGROUND_INTERVAL_MS: u64 = 15_000;
const WIFI_BACKGROUND_INTERVAL_MS: u64 = 60_000;
const WIFI_PANE_REFRESH_AGE_MS: u64 = 5_000;
const RETRY_BASE_MS: u64 = 2_000;
const RETRY_MAX_MS: u64 = 60_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DiscoveryAttempt {
    Wifi,
    BluetoothStart { adapter: AdapterId, epoch: u64 },
    BluetoothStop { adapter: AdapterId, epoch: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PendingAttempt {
    operation: OperationId,
    attempt: DiscoveryAttempt,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct OwnedBluetoothSession {
    adapter: AdapterId,
    epoch: u64,
}

#[derive(Debug)]
pub struct DiscoveryCoordinator {
    wifi_automatic: bool,
    bluetooth_desired: bool,
    wifi_pending: Option<PendingAttempt>,
    bluetooth_pending: Option<PendingAttempt>,
    bluetooth_owned: Option<OwnedBluetoothSession>,
    last_wifi_attempt_ms: Option<u64>,
    wifi_retry_after_ms: u64,
    bluetooth_retry_after_ms: u64,
    wifi_failures: u32,
    bluetooth_failures: u32,
    previous_pane: Option<Pane>,
    force_wifi_refresh: bool,
}

impl DiscoveryCoordinator {
    pub fn new(wifi_automatic: bool, bluetooth_automatic: bool) -> Self {
        Self {
            wifi_automatic,
            bluetooth_desired: bluetooth_automatic,
            wifi_pending: None,
            bluetooth_pending: None,
            bluetooth_owned: None,
            last_wifi_attempt_ms: None,
            wifi_retry_after_ms: 0,
            bluetooth_retry_after_ms: 0,
            wifi_failures: 0,
            bluetooth_failures: 0,
            previous_pane: None,
            force_wifi_refresh: false,
        }
    }

    pub fn prepare_user_intent(
        &mut self,
        intent: Intent,
        state: &AppState,
        now_ms: u64,
    ) -> Option<Intent> {
        match intent {
            Intent::ScanWifi if self.wifi_pending.is_some() => None,
            Intent::ScanWifi => Some(Intent::ScanWifi),
            Intent::ToggleBluetoothDiscovery => {
                self.bluetooth_desired = !self.bluetooth_desired;
                self.bluetooth_retry_after_ms = now_ms;
                if self.bluetooth_pending.is_some() {
                    return None;
                }
                if self.bluetooth_desired {
                    bluetooth_ready(state).then_some(Intent::StartBluetoothDiscovery)
                } else {
                    self.bluetooth_owned
                        .is_some()
                        .then_some(Intent::StopBluetoothDiscovery)
                }
            }
            intent => Some(intent),
        }
    }

    pub fn attempt_for(&self, intent: &Intent, state: &AppState) -> Option<DiscoveryAttempt> {
        match intent {
            Intent::ScanWifi | Intent::AutomaticWifiScan => Some(DiscoveryAttempt::Wifi),
            Intent::StartBluetoothDiscovery | Intent::EnsureBluetoothDiscovery => {
                bluetooth_identity(state)
                    .map(|(adapter, epoch)| DiscoveryAttempt::BluetoothStart { adapter, epoch })
            }
            Intent::StopBluetoothDiscovery | Intent::ReleaseBluetoothDiscovery => {
                bluetooth_identity(state)
                    .map(|(adapter, epoch)| DiscoveryAttempt::BluetoothStop { adapter, epoch })
            }
            _ => None,
        }
    }

    pub fn record_attempt(
        &mut self,
        attempt: Option<DiscoveryAttempt>,
        operation: Option<OperationId>,
        now_ms: u64,
    ) {
        let Some(attempt) = attempt else {
            return;
        };
        match (&attempt, operation) {
            (DiscoveryAttempt::Wifi, Some(operation)) => {
                self.last_wifi_attempt_ms = Some(now_ms);
                self.force_wifi_refresh = false;
                self.wifi_pending = Some(PendingAttempt { operation, attempt });
            }
            (DiscoveryAttempt::Wifi, None) => {
                self.last_wifi_attempt_ms = Some(now_ms);
                self.wifi_failures = self.wifi_failures.saturating_add(1);
                self.wifi_retry_after_ms = now_ms + retry_delay(self.wifi_failures);
                self.force_wifi_refresh = true;
            }
            (
                DiscoveryAttempt::BluetoothStart { .. } | DiscoveryAttempt::BluetoothStop { .. },
                Some(operation),
            ) => {
                self.bluetooth_pending = Some(PendingAttempt { operation, attempt });
            }
            (
                DiscoveryAttempt::BluetoothStart { .. } | DiscoveryAttempt::BluetoothStop { .. },
                None,
            ) => {
                self.bluetooth_failures = self.bluetooth_failures.saturating_add(1);
                self.bluetooth_retry_after_ms = now_ms + retry_delay(self.bluetooth_failures);
            }
        }
    }

    pub fn observe_event(&mut self, event: &AppEvent, now_ms: u64) {
        match event {
            AppEvent::Backend(backend) if backend.backend == BackendKind::Bluez => {
                if self
                    .bluetooth_owned
                    .as_ref()
                    .is_some_and(|owned| owned.epoch != backend.epoch)
                {
                    self.bluetooth_owned = None;
                    self.bluetooth_retry_after_ms = now_ms;
                }
                if self
                    .bluetooth_pending
                    .as_ref()
                    .is_some_and(|pending| match &pending.attempt {
                        DiscoveryAttempt::BluetoothStart { epoch, .. }
                        | DiscoveryAttempt::BluetoothStop { epoch, .. } => *epoch != backend.epoch,
                        DiscoveryAttempt::Wifi => false,
                    })
                {
                    self.bluetooth_pending = None;
                    self.bluetooth_retry_after_ms = now_ms;
                }
                if matches!(
                    backend.payload,
                    BackendPayload::Health {
                        health: crate::domain::BackendHealth::Unavailable,
                        ..
                    }
                ) {
                    self.bluetooth_owned = None;
                }
            }
            AppEvent::OperationSucceeded { id, .. } => self.finish_attempt(*id, true, now_ms),
            AppEvent::OperationFailed { id, .. } => self.finish_attempt(*id, false, now_ms),
            _ => {}
        }
    }

    pub fn observe_state(&mut self, state: &AppState, now_ms: u64) {
        let Some((adapter, epoch)) = bluetooth_identity(state) else {
            self.bluetooth_owned = None;
            self.bluetooth_pending = None;
            return;
        };
        let powered = state
            .bluetooth
            .adapters
            .get(&adapter)
            .is_some_and(|adapter| adapter.powered);
        if !powered {
            self.bluetooth_owned = None;
            self.bluetooth_pending = None;
            self.bluetooth_retry_after_ms = now_ms;
            return;
        }
        if self
            .bluetooth_owned
            .as_ref()
            .is_some_and(|owned| owned.adapter != adapter || owned.epoch != epoch)
        {
            self.bluetooth_owned = None;
            self.bluetooth_retry_after_ms = now_ms;
        }
    }

    pub fn reconcile(&mut self, state: &AppState, pane: Pane, now_ms: u64) -> Vec<Intent> {
        if self.previous_pane != Some(pane) {
            if pane == Pane::Wifi
                && self
                    .last_wifi_attempt_ms
                    .is_some_and(|last| now_ms.saturating_sub(last) >= WIFI_PANE_REFRESH_AGE_MS)
            {
                self.force_wifi_refresh = true;
            }
            self.previous_pane = Some(pane);
        }

        let mut intents = Vec::new();
        let wifi_interval = if pane == Pane::Wifi {
            WIFI_FOREGROUND_INTERVAL_MS
        } else {
            WIFI_BACKGROUND_INTERVAL_MS
        };
        let wifi_due = self.force_wifi_refresh
            || self
                .last_wifi_attempt_ms
                .is_none_or(|last| now_ms.saturating_sub(last) >= wifi_interval);
        if self.wifi_automatic
            && self.wifi_pending.is_none()
            && now_ms >= self.wifi_retry_after_ms
            && wifi_due
            && wifi_ready(state)
        {
            intents.push(Intent::AutomaticWifiScan);
        }

        if self.bluetooth_pending.is_none() && now_ms >= self.bluetooth_retry_after_ms {
            if self.bluetooth_desired {
                let owns_current = bluetooth_identity(state).is_some_and(|(adapter, epoch)| {
                    self.bluetooth_owned
                        .as_ref()
                        .is_some_and(|owned| owned.adapter == adapter && owned.epoch == epoch)
                });
                if !owns_current && bluetooth_ready(state) {
                    intents.push(Intent::EnsureBluetoothDiscovery);
                }
            } else if self.bluetooth_owned.is_some() {
                intents.push(Intent::ReleaseBluetoothDiscovery);
            }
        }
        intents
    }

    fn finish_attempt(&mut self, id: OperationId, succeeded: bool, now_ms: u64) {
        if self
            .wifi_pending
            .as_ref()
            .is_some_and(|pending| pending.operation == id)
        {
            self.wifi_pending = None;
            if succeeded {
                self.wifi_failures = 0;
                self.wifi_retry_after_ms = now_ms;
            } else {
                self.wifi_failures = self.wifi_failures.saturating_add(1);
                self.wifi_retry_after_ms = now_ms + retry_delay(self.wifi_failures);
                self.force_wifi_refresh = true;
            }
            return;
        }

        let Some(pending) = self
            .bluetooth_pending
            .take_if(|pending| pending.operation == id)
        else {
            return;
        };
        if succeeded {
            self.bluetooth_failures = 0;
            self.bluetooth_retry_after_ms = now_ms;
            match pending.attempt {
                DiscoveryAttempt::BluetoothStart { adapter, epoch } => {
                    self.bluetooth_owned = Some(OwnedBluetoothSession { adapter, epoch });
                }
                DiscoveryAttempt::BluetoothStop { .. } => self.bluetooth_owned = None,
                DiscoveryAttempt::Wifi => unreachable!(),
            }
        } else {
            self.bluetooth_failures = self.bluetooth_failures.saturating_add(1);
            self.bluetooth_retry_after_ms = now_ms + retry_delay(self.bluetooth_failures);
        }
    }
}

fn wifi_ready(state: &AppState) -> bool {
    let Some(interface_id) = state.wifi.selected_interface.as_ref() else {
        return false;
    };
    let Some(interface) = state.wifi.interfaces.get(interface_id) else {
        return false;
    };
    interface.powered
        && !interface.scanning
        && interface.capabilities.get(&Capability::Scan) == Some(&CapabilityState::Supported)
        && state
            .active_operation(&EntityId::WifiInterface(interface_id.clone()))
            .is_none()
        && !state.operations.values().any(|operation| {
            matches!(
                &operation.target,
                EntityId::Wifi(id) if id.interface == *interface_id
            )
        })
        && !state.wifi.networks.values().any(|network| {
            network.id.interface == *interface_id
                && matches!(
                    network.state,
                    ConnectionState::Associating
                        | ConnectionState::Authenticating
                        | ConnectionState::ObtainingAddress
                        | ConnectionState::Disconnecting
                )
        })
}

fn bluetooth_ready(state: &AppState) -> bool {
    bluetooth_identity(state).is_some_and(|(id, _)| {
        state.bluetooth.adapters.get(&id).is_some_and(|adapter| {
            adapter.powered
                && adapter.capabilities.get(&Capability::Scan) == Some(&CapabilityState::Supported)
        })
    })
}

fn bluetooth_identity(state: &AppState) -> Option<(AdapterId, u64)> {
    let adapter = state.bluetooth.selected_adapter.clone()?;
    state.bluetooth.adapters.get(&adapter)?;
    let epoch = state
        .backends
        .get(&BackendKind::Bluez)
        .map_or(1, |backend| backend.epoch);
    Some((adapter, epoch))
}

fn retry_delay(failures: u32) -> u64 {
    let exponent = failures.saturating_sub(1).min(5);
    RETRY_BASE_MS
        .saturating_mul(1_u64 << exponent)
        .min(RETRY_MAX_MS)
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeMap;

    use super::*;
    use crate::domain::{
        AdapterId, BackendHealth, BackendState, BluetoothAdapter, Connectivity, InterfaceId, Ssid,
        WifiInterface, WifiNetwork, WifiNetworkId, WifiSecurity,
    };

    fn ready_state() -> AppState {
        let mut state = AppState::default();
        let interface = InterfaceId("wlan0".into());
        state.wifi.selected_interface = Some(interface.clone());
        state.wifi.interfaces.insert(
            interface.clone(),
            WifiInterface {
                id: interface,
                backend: BackendKind::NetworkManager,
                powered: true,
                scanning: false,
                last_scan_ms: None,
                addresses: Vec::new(),
                capabilities: BTreeMap::from([(Capability::Scan, CapabilityState::Supported)]),
            },
        );
        let adapter = AdapterId("hci0".into());
        state.bluetooth.selected_adapter = Some(adapter.clone());
        state.bluetooth.adapters.insert(
            adapter.clone(),
            BluetoothAdapter {
                id: adapter,
                powered: true,
                scanning: false,
                capabilities: BTreeMap::from([(Capability::Scan, CapabilityState::Supported)]),
            },
        );
        state.backends.insert(
            BackendKind::Bluez,
            BackendState {
                health: BackendHealth::Ready,
                epoch: 1,
                revision: 1,
                last_observed_ms: 0,
                detail: None,
            },
        );
        state
    }

    #[test]
    fn starts_both_discovery_paths_as_soon_as_radios_are_ready() {
        let mut coordinator = DiscoveryCoordinator::new(true, true);
        let intents = coordinator.reconcile(&ready_state(), Pane::Wifi, 0);
        assert!(intents
            .iter()
            .any(|intent| matches!(intent, Intent::AutomaticWifiScan)));
        assert!(intents
            .iter()
            .any(|intent| matches!(intent, Intent::EnsureBluetoothDiscovery)));
    }

    #[test]
    fn reacquires_bluetooth_session_after_bluez_epoch_change() {
        let mut coordinator = DiscoveryCoordinator::new(false, true);
        let mut state = ready_state();
        let start = Intent::StartBluetoothDiscovery;
        let attempt = coordinator.attempt_for(&start, &state);
        coordinator.record_attempt(attempt, Some(OperationId(7)), 0);
        coordinator.observe_event(
            &AppEvent::OperationSucceeded {
                id: OperationId(7),
                message: "started".into(),
                timestamp_ms: 1,
            },
            1,
        );
        assert!(coordinator.reconcile(&state, Pane::Wifi, 1).is_empty());

        state.backends.get_mut(&BackendKind::Bluez).unwrap().epoch = 2;
        coordinator.observe_event(
            &AppEvent::Backend(crate::domain::BackendEvent {
                backend: BackendKind::Bluez,
                epoch: 2,
                revision: 1,
                observed_at_ms: 2,
                payload: BackendPayload::Health {
                    health: BackendHealth::Reconnecting,
                    detail: None,
                },
            }),
            2,
        );
        assert!(matches!(
            coordinator.reconcile(&state, Pane::Wifi, 2).as_slice(),
            [Intent::EnsureBluetoothDiscovery]
        ));
    }

    #[test]
    fn reacquires_bluetooth_session_after_adapter_power_cycle() {
        let mut coordinator = DiscoveryCoordinator::new(false, true);
        let mut state = ready_state();
        let start = coordinator.attempt_for(&Intent::EnsureBluetoothDiscovery, &state);
        coordinator.record_attempt(start, Some(OperationId(70)), 0);
        coordinator.observe_event(
            &AppEvent::OperationSucceeded {
                id: OperationId(70),
                message: "started".into(),
                timestamp_ms: 1,
            },
            1,
        );

        state
            .bluetooth
            .adapters
            .get_mut(&AdapterId("hci0".into()))
            .unwrap()
            .powered = false;
        coordinator.observe_state(&state, 2);
        state
            .bluetooth
            .adapters
            .get_mut(&AdapterId("hci0".into()))
            .unwrap()
            .powered = true;

        assert!(matches!(
            coordinator.reconcile(&state, Pane::Bluetooth, 3).as_slice(),
            [Intent::EnsureBluetoothDiscovery]
        ));
    }

    #[test]
    fn manual_bluetooth_toggle_controls_our_session_not_global_state() {
        let mut coordinator = DiscoveryCoordinator::new(false, true);
        let mut state = ready_state();
        state
            .bluetooth
            .adapters
            .get_mut(&AdapterId("hci0".into()))
            .unwrap()
            .scanning = true;
        let attempt = coordinator.attempt_for(&Intent::StartBluetoothDiscovery, &state);
        coordinator.record_attempt(attempt, Some(OperationId(8)), 0);
        coordinator.observe_event(
            &AppEvent::OperationSucceeded {
                id: OperationId(8),
                message: "started".into(),
                timestamp_ms: 1,
            },
            1,
        );

        assert!(matches!(
            coordinator.prepare_user_intent(Intent::ToggleBluetoothDiscovery, &state, 2),
            Some(Intent::StopBluetoothDiscovery)
        ));
    }

    #[test]
    fn failed_manual_stop_is_retried_without_losing_session_ownership() {
        let mut coordinator = DiscoveryCoordinator::new(false, true);
        let state = ready_state();
        let start = coordinator.attempt_for(&Intent::StartBluetoothDiscovery, &state);
        coordinator.record_attempt(start, Some(OperationId(11)), 0);
        coordinator.observe_event(
            &AppEvent::OperationSucceeded {
                id: OperationId(11),
                message: "started".into(),
                timestamp_ms: 1,
            },
            1,
        );
        assert!(matches!(
            coordinator.prepare_user_intent(Intent::ToggleBluetoothDiscovery, &state, 2),
            Some(Intent::StopBluetoothDiscovery)
        ));
        let stop = coordinator.attempt_for(&Intent::StopBluetoothDiscovery, &state);
        coordinator.record_attempt(stop, Some(OperationId(12)), 2);
        coordinator.observe_event(
            &AppEvent::OperationFailed {
                id: OperationId(12),
                error: crate::domain::UserFacingError {
                    category: crate::domain::ErrorCategory::Busy,
                    summary: "busy".into(),
                    detail: "busy".into(),
                    recovery: Vec::new(),
                    retryable: true,
                    backend: Some(BackendKind::Bluez),
                    target: None,
                    raw_code: None,
                },
                timestamp_ms: 3,
            },
            3,
        );

        assert!(matches!(
            coordinator
                .reconcile(&state, Pane::Bluetooth, 2_003)
                .as_slice(),
            [Intent::ReleaseBluetoothDiscovery]
        ));
    }

    #[test]
    fn wifi_scan_retries_with_backoff_and_refreshes_on_pane_return() {
        let mut coordinator = DiscoveryCoordinator::new(true, false);
        let state = ready_state();
        let attempt = coordinator.attempt_for(&Intent::ScanWifi, &state);
        coordinator.record_attempt(attempt, Some(OperationId(9)), 0);
        coordinator.observe_event(
            &AppEvent::OperationFailed {
                id: OperationId(9),
                error: crate::domain::UserFacingError {
                    category: crate::domain::ErrorCategory::Busy,
                    summary: "busy".into(),
                    detail: "busy".into(),
                    recovery: Vec::new(),
                    retryable: true,
                    backend: Some(BackendKind::NetworkManager),
                    target: None,
                    raw_code: None,
                },
                timestamp_ms: 1,
            },
            1,
        );
        assert!(coordinator.reconcile(&state, Pane::Wifi, 2_000).is_empty());
        assert!(matches!(
            coordinator.reconcile(&state, Pane::Wifi, 2_001).as_slice(),
            [Intent::AutomaticWifiScan]
        ));

        let attempt = coordinator.attempt_for(&Intent::ScanWifi, &state);
        coordinator.record_attempt(attempt, Some(OperationId(10)), 2_001);
        coordinator.observe_event(
            &AppEvent::OperationSucceeded {
                id: OperationId(10),
                message: "started".into(),
                timestamp_ms: 2_002,
            },
            2_002,
        );
        assert!(coordinator
            .reconcile(&state, Pane::Bluetooth, 8_000)
            .is_empty());
        assert!(matches!(
            coordinator.reconcile(&state, Pane::Wifi, 8_001).as_slice(),
            [Intent::AutomaticWifiScan]
        ));
    }

    #[test]
    fn automatic_wifi_scan_waits_for_association_to_finish() {
        let mut coordinator = DiscoveryCoordinator::new(true, false);
        let mut state = ready_state();
        let id = WifiNetworkId {
            interface: InterfaceId("wlan0".into()),
            ssid: Ssid(b"Home".to_vec()),
            security: WifiSecurity::Personal,
        };
        state.wifi.networks.insert(
            id.clone(),
            WifiNetwork {
                id,
                display_name: "Home".into(),
                signal: 80,
                state: ConnectionState::Authenticating,
                connectivity: Connectivity::None,
                saved: true,
                auto_join: true,
                bss_count: 1,
                active_bssid: None,
                present: true,
                last_seen_ms: 0,
            },
        );

        assert!(coordinator.reconcile(&state, Pane::Wifi, 0).is_empty());
        state.wifi.networks.values_mut().next().unwrap().state = ConnectionState::Connected;
        assert!(matches!(
            coordinator.reconcile(&state, Pane::Wifi, 1).as_slice(),
            [Intent::AutomaticWifiScan]
        ));
    }
}
