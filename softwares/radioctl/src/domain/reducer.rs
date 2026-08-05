use std::cmp::Ordering;
use std::collections::BTreeMap;

use super::{
    ActivityEntry, ActivityLevel, AppState, BackendEvent, BackendPayload, BackendState,
    BluetoothDevice, BluetoothDeviceId, BluetoothSnapshot, Operation, OperationId, OperationPhase,
    UserFacingError, WifiNetwork, WifiNetworkId, WifiSnapshot,
};

const MISSING_SELECTION_RETENTION_MS: u64 = 30_000;

#[derive(Debug, Clone)]
pub enum AppEvent {
    Backend(BackendEvent),
    OperationStarted(Operation),
    OperationProgress {
        id: OperationId,
        phase: OperationPhase,
        timestamp_ms: u64,
    },
    OperationSucceeded {
        id: OperationId,
        message: String,
        timestamp_ms: u64,
    },
    OperationFailed {
        id: OperationId,
        error: UserFacingError,
        timestamp_ms: u64,
    },
    SelectWifi(Option<WifiNetworkId>),
    SelectBluetooth(Option<BluetoothDeviceId>),
    DismissError,
    Tick(u64),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReduceOutcome {
    Changed,
    IgnoredStale,
    Unchanged,
}

#[derive(Debug, Default)]
pub struct Reducer {
    pub state: AppState,
}

impl Reducer {
    pub fn apply(&mut self, event: AppEvent) -> ReduceOutcome {
        match event {
            AppEvent::Backend(event) => self.apply_backend(event),
            AppEvent::OperationStarted(operation) => self.start_operation(operation),
            AppEvent::OperationProgress {
                id,
                phase,
                timestamp_ms,
            } => self.progress_operation(id, phase, timestamp_ms),
            AppEvent::OperationSucceeded {
                id,
                message,
                timestamp_ms,
            } => self.finish_operation(id, Ok(message), timestamp_ms),
            AppEvent::OperationFailed {
                id,
                error,
                timestamp_ms,
            } => self.finish_operation(id, Err(error), timestamp_ms),
            AppEvent::SelectWifi(selected) => {
                if self.state.wifi.selected == selected {
                    ReduceOutcome::Unchanged
                } else {
                    self.state.wifi.selected = selected;
                    ReduceOutcome::Changed
                }
            }
            AppEvent::SelectBluetooth(selected) => {
                if self.state.bluetooth.selected == selected {
                    ReduceOutcome::Unchanged
                } else {
                    self.state.bluetooth.selected = selected;
                    ReduceOutcome::Changed
                }
            }
            AppEvent::DismissError => {
                if self.state.current_error.take().is_some() {
                    ReduceOutcome::Changed
                } else {
                    ReduceOutcome::Unchanged
                }
            }
            AppEvent::Tick(now_ms) => self.expire_missing(now_ms),
        }
    }

    fn apply_backend(&mut self, event: BackendEvent) -> ReduceOutcome {
        if let Some(clock) = self.state.backends.get(&event.backend) {
            if event.epoch < clock.epoch
                || (event.epoch == clock.epoch && event.revision <= clock.revision)
            {
                return ReduceOutcome::IgnoredStale;
            }
        }

        let previous_epoch = self
            .state
            .backends
            .get(&event.backend)
            .map_or(event.epoch, |state| state.epoch);
        let default_health = self
            .state
            .backends
            .get(&event.backend)
            .map_or(super::BackendHealth::Ready, |state| state.health);

        let (health, detail) = match &event.payload {
            BackendPayload::Health { health, detail } => (*health, detail.clone()),
            _ => (default_health, None),
        };

        self.state.backends.insert(
            event.backend,
            BackendState {
                health,
                epoch: event.epoch,
                revision: event.revision,
                last_observed_ms: event.observed_at_ms,
                detail,
            },
        );

        if event.epoch > previous_epoch {
            self.cancel_operations_from_epoch(event.backend, previous_epoch, event.observed_at_ms);
        }

        match event.payload {
            BackendPayload::WifiSnapshot(snapshot) => {
                self.apply_wifi_snapshot(snapshot, event.observed_at_ms)
            }
            BackendPayload::BluetoothSnapshot(snapshot) => {
                self.apply_bluetooth_snapshot(snapshot, event.observed_at_ms)
            }
            BackendPayload::Health { .. } => {}
        }
        ReduceOutcome::Changed
    }

    fn apply_wifi_snapshot(&mut self, snapshot: WifiSnapshot, now_ms: u64) {
        self.state.wifi.interfaces = snapshot
            .interfaces
            .into_iter()
            .map(|interface| (interface.id.clone(), interface))
            .collect();
        if self
            .state
            .wifi
            .selected_interface
            .as_ref()
            .is_none_or(|id| !self.state.wifi.interfaces.contains_key(id))
        {
            self.state.wifi.selected_interface = self.state.wifi.interfaces.keys().next().cloned();
        }

        let incoming: BTreeMap<_, _> = snapshot
            .networks
            .into_iter()
            .map(|mut network| {
                network.present = true;
                (network.id.clone(), network)
            })
            .collect();
        let selected = self.state.wifi.selected.clone();
        let mut merged = incoming;

        if let Some(selected_id) = selected.as_ref() {
            if !merged.contains_key(selected_id) {
                if let Some(mut missing) = self.state.wifi.networks.get(selected_id).cloned() {
                    if now_ms.saturating_sub(missing.last_seen_ms) <= MISSING_SELECTION_RETENTION_MS
                    {
                        missing.present = false;
                        merged.insert(selected_id.clone(), missing);
                    }
                }
            }
        }

        self.state.wifi.order = stable_wifi_order(&self.state.wifi.order, &merged);
        self.state.wifi.networks = merged;
        self.state.wifi.selected = preserve_or_first(selected, &self.state.wifi.order);
    }

    fn apply_bluetooth_snapshot(&mut self, snapshot: BluetoothSnapshot, now_ms: u64) {
        self.state.bluetooth.adapters = snapshot
            .adapters
            .into_iter()
            .map(|adapter| (adapter.id.clone(), adapter))
            .collect();
        if self
            .state
            .bluetooth
            .selected_adapter
            .as_ref()
            .is_none_or(|id| !self.state.bluetooth.adapters.contains_key(id))
        {
            self.state.bluetooth.selected_adapter =
                self.state.bluetooth.adapters.keys().next().cloned();
        }

        let incoming: BTreeMap<_, _> = snapshot
            .devices
            .into_iter()
            .map(|mut device| {
                device.present = true;
                (device.id.clone(), device)
            })
            .collect();
        let selected = self.state.bluetooth.selected.clone();
        let mut merged = incoming;

        if let Some(selected_id) = selected.as_ref() {
            if !merged.contains_key(selected_id) {
                if let Some(mut missing) = self.state.bluetooth.devices.get(selected_id).cloned() {
                    if now_ms.saturating_sub(missing.last_seen_ms) <= MISSING_SELECTION_RETENTION_MS
                    {
                        missing.present = false;
                        merged.insert(selected_id.clone(), missing);
                    }
                }
            }
        }

        self.state.bluetooth.order = stable_bluetooth_order(&self.state.bluetooth.order, &merged);
        self.state.bluetooth.devices = merged;
        self.state.bluetooth.selected = preserve_or_first(selected, &self.state.bluetooth.order);
    }

    fn start_operation(&mut self, operation: Operation) -> ReduceOutcome {
        if let Some(previous_id) = self
            .state
            .active_operation_by_target
            .insert(operation.target.clone(), operation.id)
        {
            self.state.operations.remove(&previous_id);
            self.state.push_activity(ActivityEntry {
                timestamp_ms: operation.started_at_ms,
                level: ActivityLevel::Warning,
                message: format!("operation {} was superseded", previous_id.0),
                operation: Some(previous_id),
            });
        }

        self.state.push_activity(ActivityEntry {
            timestamp_ms: operation.started_at_ms,
            level: ActivityLevel::Info,
            message: format!("operation {} queued", operation.id.0),
            operation: Some(operation.id),
        });
        self.state.operations.insert(operation.id, operation);
        ReduceOutcome::Changed
    }

    fn progress_operation(
        &mut self,
        id: OperationId,
        phase: OperationPhase,
        timestamp_ms: u64,
    ) -> ReduceOutcome {
        let Some(operation) = self.state.operations.get_mut(&id) else {
            return ReduceOutcome::IgnoredStale;
        };
        operation.phase = phase.clone();
        self.state.push_activity(ActivityEntry {
            timestamp_ms,
            level: ActivityLevel::Info,
            message: format_operation_phase(&phase),
            operation: Some(id),
        });
        ReduceOutcome::Changed
    }

    fn finish_operation(
        &mut self,
        id: OperationId,
        result: Result<String, UserFacingError>,
        timestamp_ms: u64,
    ) -> ReduceOutcome {
        let Some(operation) = self.state.operations.remove(&id) else {
            return ReduceOutcome::IgnoredStale;
        };
        if self.state.active_operation_by_target.get(&operation.target) != Some(&id) {
            return ReduceOutcome::IgnoredStale;
        }
        self.state
            .active_operation_by_target
            .remove(&operation.target);

        match result {
            Ok(message) => self.state.push_activity(ActivityEntry {
                timestamp_ms,
                level: ActivityLevel::Success,
                message,
                operation: Some(id),
            }),
            Err(error) => {
                self.state.push_activity(ActivityEntry {
                    timestamp_ms,
                    level: ActivityLevel::Error,
                    message: error.summary.clone(),
                    operation: Some(id),
                });
                self.state.current_error = Some(error);
            }
        }
        ReduceOutcome::Changed
    }

    fn cancel_operations_from_epoch(
        &mut self,
        backend: super::BackendKind,
        epoch: u64,
        timestamp_ms: u64,
    ) {
        let stale = self
            .state
            .operations
            .values()
            .filter(|operation| operation.backend == backend && operation.backend_epoch <= epoch)
            .map(|operation| operation.id)
            .collect::<Vec<_>>();
        for id in stale {
            if let Some(operation) = self.state.operations.remove(&id) {
                self.state
                    .active_operation_by_target
                    .remove(&operation.target);
                self.state.push_activity(ActivityEntry {
                    timestamp_ms,
                    level: ActivityLevel::Warning,
                    message: format!("{backend} restarted; operation {} will be reconciled", id.0),
                    operation: Some(id),
                });
            }
        }
    }

    fn expire_missing(&mut self, now_ms: u64) -> ReduceOutcome {
        let wifi_before = self.state.wifi.networks.len();
        let selected_wifi = self.state.wifi.selected.clone();
        self.state.wifi.networks.retain(|id, network| {
            network.present
                || (selected_wifi.as_ref() == Some(id)
                    && now_ms.saturating_sub(network.last_seen_ms)
                        <= MISSING_SELECTION_RETENTION_MS)
        });
        self.state
            .wifi
            .order
            .retain(|id| self.state.wifi.networks.contains_key(id));
        if self
            .state
            .wifi
            .selected
            .as_ref()
            .is_some_and(|id| !self.state.wifi.networks.contains_key(id))
        {
            self.state.wifi.selected = self.state.wifi.order.first().cloned();
        }

        let bt_before = self.state.bluetooth.devices.len();
        let selected_bt = self.state.bluetooth.selected.clone();
        self.state.bluetooth.devices.retain(|id, device| {
            device.present
                || (selected_bt.as_ref() == Some(id)
                    && now_ms.saturating_sub(device.last_seen_ms) <= MISSING_SELECTION_RETENTION_MS)
        });
        self.state
            .bluetooth
            .order
            .retain(|id| self.state.bluetooth.devices.contains_key(id));
        if self
            .state
            .bluetooth
            .selected
            .as_ref()
            .is_some_and(|id| !self.state.bluetooth.devices.contains_key(id))
        {
            self.state.bluetooth.selected = self.state.bluetooth.order.first().cloned();
        }

        if wifi_before != self.state.wifi.networks.len()
            || bt_before != self.state.bluetooth.devices.len()
        {
            ReduceOutcome::Changed
        } else {
            ReduceOutcome::Unchanged
        }
    }
}

fn preserve_or_first<T: Clone + PartialEq>(selected: Option<T>, order: &[T]) -> Option<T> {
    selected
        .filter(|id| order.contains(id))
        .or_else(|| order.first().cloned())
}

fn stable_wifi_order(
    previous: &[WifiNetworkId],
    networks: &BTreeMap<WifiNetworkId, WifiNetwork>,
) -> Vec<WifiNetworkId> {
    stable_order(previous, networks, |left, right| {
        wifi_section(left)
            .cmp(&wifi_section(right))
            .then_with(|| right.saved.cmp(&left.saved))
    })
}

fn wifi_section(network: &WifiNetwork) -> u8 {
    match network.state {
        super::ConnectionState::Connected => 0,
        super::ConnectionState::Associating
        | super::ConnectionState::Authenticating
        | super::ConnectionState::ObtainingAddress
        | super::ConnectionState::Disconnecting => 1,
        _ if network.saved => 2,
        _ => 3,
    }
}

fn stable_bluetooth_order(
    previous: &[BluetoothDeviceId],
    devices: &BTreeMap<BluetoothDeviceId, BluetoothDevice>,
) -> Vec<BluetoothDeviceId> {
    stable_order(previous, devices, |left, right| {
        bluetooth_section(left).cmp(&bluetooth_section(right))
    })
}

fn bluetooth_section(device: &BluetoothDevice) -> u8 {
    match device.state {
        super::ConnectionState::Connected => 0,
        super::ConnectionState::Associating
        | super::ConnectionState::Authenticating
        | super::ConnectionState::ObtainingAddress
        | super::ConnectionState::Disconnecting => 1,
        _ if device.paired => 2,
        _ => 3,
    }
}

fn stable_order<K, V, F>(previous: &[K], values: &BTreeMap<K, V>, compare: F) -> Vec<K>
where
    K: Clone + Ord,
    F: Fn(&V, &V) -> Ordering,
{
    let previous_positions = previous
        .iter()
        .enumerate()
        .map(|(index, id)| (id, index))
        .collect::<BTreeMap<_, _>>();
    let mut order = values.keys().cloned().collect::<Vec<_>>();
    order.sort_by(|left, right| {
        compare(&values[left], &values[right]).then_with(|| {
            previous_positions
                .get(left)
                .copied()
                .unwrap_or(usize::MAX)
                .cmp(&previous_positions.get(right).copied().unwrap_or(usize::MAX))
                .then_with(|| left.cmp(right))
        })
    });
    order
}

fn format_operation_phase(phase: &OperationPhase) -> String {
    match phase {
        OperationPhase::Queued => "queued".to_owned(),
        OperationPhase::Running(message) | OperationPhase::AwaitingConfirmation(message) => {
            message.clone()
        }
        OperationPhase::Reconciling => "final state unknown; reconciling".to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use proptest::prelude::*;

    use super::*;
    use crate::domain::{
        AdapterId, BackendHealth, BackendKind, BluetoothAdapter, BluetoothDeviceId,
        ConnectionState, Connectivity, EntityId, ErrorCategory, HardwareAddress, InterfaceId, Ssid,
        WifiInterface, WifiNetworkId, WifiSecurity, ACTIVITY_CAPACITY,
    };

    fn wifi_id(name: &[u8]) -> WifiNetworkId {
        WifiNetworkId {
            interface: InterfaceId("wlan0".into()),
            ssid: Ssid(name.to_vec()),
            security: WifiSecurity::Personal,
        }
    }

    fn wifi_network(name: &[u8], state: ConnectionState, now: u64) -> WifiNetwork {
        let id = wifi_id(name);
        WifiNetwork {
            display_name: id.ssid.display(),
            id,
            signal: 50,
            state,
            connectivity: Connectivity::Unknown,
            saved: false,
            auto_join: false,
            bss_count: 1,
            active_bssid: None,
            present: true,
            last_seen_ms: now,
        }
    }

    fn wifi_event(revision: u64, networks: Vec<WifiNetwork>) -> AppEvent {
        AppEvent::Backend(BackendEvent {
            backend: BackendKind::NetworkManager,
            epoch: 1,
            revision,
            observed_at_ms: revision * 10,
            payload: BackendPayload::WifiSnapshot(WifiSnapshot {
                interfaces: vec![WifiInterface {
                    id: InterfaceId("wlan0".into()),
                    backend: BackendKind::NetworkManager,
                    powered: true,
                    scanning: false,
                    last_scan_ms: None,
                    capabilities: BTreeMap::new(),
                }],
                networks,
            }),
        })
    }

    #[test]
    fn focus_follows_connected_network_when_it_moves() {
        let mut reducer = Reducer::default();
        reducer.apply(wifi_event(
            1,
            vec![
                wifi_network(b"first", ConnectionState::Disconnected, 10),
                wifi_network(b"second", ConnectionState::Disconnected, 10),
            ],
        ));
        reducer.apply(AppEvent::SelectWifi(Some(wifi_id(b"second"))));
        reducer.apply(wifi_event(
            2,
            vec![
                wifi_network(b"first", ConnectionState::Disconnected, 20),
                wifi_network(b"second", ConnectionState::Connected, 20),
            ],
        ));

        assert_eq!(reducer.state.wifi.order[0], wifi_id(b"second"));
        assert_eq!(reducer.state.wifi.selected, Some(wifi_id(b"second")));
    }

    #[test]
    fn selected_missing_network_is_retained_without_stealing_focus() {
        let mut reducer = Reducer::default();
        reducer.apply(wifi_event(
            1,
            vec![wifi_network(b"unstable", ConnectionState::Disconnected, 10)],
        ));
        reducer.apply(wifi_event(2, vec![]));

        let network = &reducer.state.wifi.networks[&wifi_id(b"unstable")];
        assert!(!network.present);
        assert_eq!(reducer.state.wifi.selected, Some(wifi_id(b"unstable")));

        reducer.apply(AppEvent::Tick(30_011));
        assert!(reducer.state.wifi.networks.is_empty());
        assert_eq!(reducer.state.wifi.selected, None);
    }

    #[test]
    fn stale_backend_event_cannot_replace_newer_state() {
        let mut reducer = Reducer::default();
        let mut strong = wifi_network(b"network", ConnectionState::Connected, 20);
        strong.signal = 90;
        reducer.apply(wifi_event(2, vec![strong]));

        let mut stale = wifi_network(b"network", ConnectionState::Disconnected, 10);
        stale.signal = 1;
        assert_eq!(
            reducer.apply(wifi_event(1, vec![stale])),
            ReduceOutcome::IgnoredStale
        );
        assert_eq!(reducer.state.wifi.networks[&wifi_id(b"network")].signal, 90);
    }

    #[test]
    fn superseded_operation_completion_is_ignored() {
        let mut reducer = Reducer::default();
        let target = EntityId::Wifi(wifi_id(b"network"));
        for id in [1, 2] {
            reducer.apply(AppEvent::OperationStarted(Operation {
                id: OperationId(id),
                backend: BackendKind::NetworkManager,
                target: target.clone(),
                desired: super::super::DesiredState::Connected,
                phase: OperationPhase::Queued,
                started_at_ms: id,
                deadline_ms: 100,
                backend_epoch: 1,
            }));
        }

        assert_eq!(
            reducer.apply(AppEvent::OperationSucceeded {
                id: OperationId(1),
                message: "old success".into(),
                timestamp_ms: 3,
            }),
            ReduceOutcome::IgnoredStale
        );
        assert_eq!(
            reducer.state.active_operation(&target).unwrap().id,
            OperationId(2)
        );
    }

    #[test]
    fn errors_are_persistent_and_activity_is_bounded() {
        let mut reducer = Reducer::default();
        let target = EntityId::Wifi(wifi_id(b"network"));
        for id in 0..=ACTIVITY_CAPACITY as u64 {
            reducer.apply(AppEvent::OperationStarted(Operation {
                id: OperationId(id),
                backend: BackendKind::NetworkManager,
                target: EntityId::Wifi(wifi_id(format!("network-{id}").as_bytes())),
                desired: super::super::DesiredState::Connected,
                phase: OperationPhase::Queued,
                started_at_ms: id,
                deadline_ms: id + 100,
                backend_epoch: 1,
            }));
        }
        assert_eq!(reducer.state.activity.len(), ACTIVITY_CAPACITY);

        let id = OperationId(9_999);
        reducer.apply(AppEvent::OperationStarted(Operation {
            id,
            backend: BackendKind::NetworkManager,
            target,
            desired: super::super::DesiredState::Connected,
            phase: OperationPhase::Queued,
            started_at_ms: 1,
            deadline_ms: 2,
            backend_epoch: 1,
        }));
        reducer.apply(AppEvent::OperationFailed {
            id,
            error: UserFacingError {
                category: ErrorCategory::Authentication,
                summary: "Password rejected".into(),
                detail: "The access point rejected the supplied secret".into(),
                recovery: vec!["Retry with a new password".into()],
                retryable: true,
                backend: Some(BackendKind::NetworkManager),
                target: None,
                raw_code: Some("no-secrets".into()),
            },
            timestamp_ms: 2,
        });
        assert_eq!(
            reducer.state.current_error.as_ref().unwrap().summary,
            "Password rejected"
        );
    }

    #[test]
    fn raw_ssids_have_unambiguous_display_text() {
        assert_eq!(
            Ssid(vec![b'a', 0, b'\\', 0xff]).display(),
            "a\\x00\\\\\\xff"
        );
        assert_eq!(Ssid("café".as_bytes().to_vec()).display(), "café");
    }

    #[test]
    fn bluetooth_snapshot_selects_first_device() {
        let id = BluetoothDeviceId {
            adapter: AdapterId("hci0".into()),
            address: HardwareAddress("00:11:22:33:44:55".into()),
        };
        let mut reducer = Reducer::default();
        reducer.apply(AppEvent::Backend(BackendEvent {
            backend: BackendKind::Bluez,
            epoch: 1,
            revision: 1,
            observed_at_ms: 1,
            payload: BackendPayload::BluetoothSnapshot(BluetoothSnapshot {
                adapters: vec![BluetoothAdapter {
                    id: AdapterId("hci0".into()),
                    powered: true,
                    scanning: false,
                    capabilities: BTreeMap::new(),
                }],
                devices: vec![BluetoothDevice {
                    id: id.clone(),
                    name: "Keyboard".into(),
                    state: ConnectionState::Disconnected,
                    paired: true,
                    trusted: true,
                    blocked: false,
                    services_resolved: true,
                    rssi: None,
                    battery_percent: None,
                    present: true,
                    last_seen_ms: 1,
                }],
            }),
        }));
        assert_eq!(reducer.state.bluetooth.selected, Some(id));
    }

    #[test]
    fn newer_epoch_accepts_revision_reset() {
        let mut reducer = Reducer::default();
        reducer.apply(wifi_event(
            20,
            vec![wifi_network(b"old", ConnectionState::Connected, 20)],
        ));
        let outcome = reducer.apply(AppEvent::Backend(BackendEvent {
            backend: BackendKind::NetworkManager,
            epoch: 2,
            revision: 1,
            observed_at_ms: 30,
            payload: BackendPayload::Health {
                health: BackendHealth::Reconnecting,
                detail: Some("daemon owner changed".into()),
            },
        }));
        assert_eq!(outcome, ReduceOutcome::Changed);
        assert_eq!(
            reducer.state.backends[&BackendKind::NetworkManager].epoch,
            2
        );
    }

    proptest! {
        #[test]
        fn event_order_never_allows_a_lower_revision_to_win(
            revisions in prop::collection::vec(1_u64..100, 1..100)
        ) {
            let mut reducer = Reducer::default();
            for revision in &revisions {
                let mut network = wifi_network(b"network", ConnectionState::Disconnected, *revision);
                network.signal = *revision as u8;
                reducer.apply(wifi_event(*revision, vec![network]));
            }
            let maximum = *revisions.iter().max().unwrap();
            prop_assert_eq!(
                reducer.state.wifi.networks[&wifi_id(b"network")].signal,
                maximum as u8
            );
        }
    }
}
