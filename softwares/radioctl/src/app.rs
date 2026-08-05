use crossterm::event::{
    Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent, MouseEventKind,
};
use ratatui::layout::Rect;
use zeroize::Zeroizing;

use crate::{
    backend::Secret,
    domain::{
        ActivityEntry, ActivityLevel, AppEvent, BluetoothDeviceId, Capability, CapabilityState,
        ConnectionState, DesiredState, EntityId, ErrorCategory, OperationId, Reducer,
        UserFacingError, WifiNetworkId, WifiSecurity,
    },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pane {
    Wifi,
    Bluetooth,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Overlay {
    Help,
    Activity,
    Palette,
    Search,
    Credential,
    Diagnostics,
    Error,
    Confirm,
    WifiShare,
}

#[derive(Debug)]
pub enum Intent {
    Quit,
    SetConnection {
        target: EntityId,
        desired: DesiredState,
        credential: Option<Secret>,
    },
    Cancel(OperationId),
    ScanWifi,
    ToggleBluetoothDiscovery,
    StartBluetoothDiscovery,
    ToggleWifiRadio,
    ToggleBluetoothRadio,
    OpenDiagnostics,
    Forget(EntityId),
    SetWifiAutoJoin {
        id: WifiNetworkId,
        enabled: bool,
    },
    ShowWifiSecret {
        id: WifiNetworkId,
        qr: bool,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PaletteAction {
    ToggleWifi,
    ScanWifi,
    ToggleBluetooth,
    DiscoverBluetooth,
    Diagnostics,
    ToggleAutoJoin,
    ForgetWifi,
    ShowWifiPassword,
    ShowWifiQr,
    ForgetBluetooth,
    Activity,
    Help,
    Quit,
}

impl PaletteAction {
    pub const ALL: [Self; 13] = [
        Self::ToggleWifi,
        Self::ScanWifi,
        Self::ToggleBluetooth,
        Self::DiscoverBluetooth,
        Self::Diagnostics,
        Self::ToggleAutoJoin,
        Self::ForgetWifi,
        Self::ShowWifiPassword,
        Self::ShowWifiQr,
        Self::ForgetBluetooth,
        Self::Activity,
        Self::Help,
        Self::Quit,
    ];

    pub fn label(self) -> &'static str {
        match self {
            Self::ToggleWifi => "Toggle Wi-Fi radio",
            Self::ScanWifi => "Scan for Wi-Fi networks",
            Self::ToggleBluetooth => "Toggle Bluetooth radio",
            Self::DiscoverBluetooth => "Discover Bluetooth devices",
            Self::Diagnostics => "Open diagnostics",
            Self::ToggleAutoJoin => "Toggle auto-join for selected Wi-Fi network",
            Self::ForgetWifi => "Forget selected Wi-Fi network",
            Self::ShowWifiPassword => "Show saved Wi-Fi password",
            Self::ShowWifiQr => "Show Wi-Fi QR code",
            Self::ForgetBluetooth => "Forget selected Bluetooth device",
            Self::Activity => "Open activity journal",
            Self::Help => "Open keyboard help",
            Self::Quit => "Quit radioctl",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EntryAction {
    ToggleConnection,
    ToggleAutoJoin,
    ShowPassword,
    ShowQr,
    Forget,
}

#[derive(Debug, Default, Clone, Copy)]
pub struct ListHitArea {
    pub area: Option<Rect>,
    pub first_visible_row: usize,
}

#[derive(Debug)]
pub struct Application {
    pub reducer: Reducer,
    pub pane: Pane,
    pub overlay: Option<Overlay>,
    pub search: String,
    pub palette_query: String,
    pub palette_selected: usize,
    pub list_hit_area: ListHitArea,
    pub diagnostics: Vec<String>,
    pub detail_action_hit_areas: Vec<(Rect, EntryAction)>,
    wifi_list_offset: usize,
    bluetooth_list_offset: usize,
    credential_target: Option<EntityId>,
    credential: CredentialBuffer,
    credential_revealed: bool,
    confirmation_target: Option<EntityId>,
    wifi_share: Option<WifiShare>,
    quit: bool,
}

#[derive(Default)]
struct CredentialBuffer(Zeroizing<String>);

struct WifiShare {
    network_name: String,
    password: Secret,
    qr: Option<Zeroizing<String>>,
}

impl std::fmt::Debug for WifiShare {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("WifiShare([REDACTED])")
    }
}

impl std::fmt::Debug for CredentialBuffer {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("CredentialBuffer([REDACTED])")
    }
}

impl Default for Application {
    fn default() -> Self {
        Self::new()
    }
}

impl Application {
    pub fn new() -> Self {
        let mut reducer = Reducer::default();
        reducer.state.push_activity(ActivityEntry {
            timestamp_ms: 0,
            level: ActivityLevel::Info,
            message: "radioctl started; probing radio services".into(),
            operation: None,
        });
        Self {
            reducer,
            pane: Pane::Wifi,
            overlay: None,
            search: String::new(),
            palette_query: String::new(),
            palette_selected: 0,
            list_hit_area: ListHitArea::default(),
            diagnostics: Vec::new(),
            detail_action_hit_areas: Vec::new(),
            wifi_list_offset: 0,
            bluetooth_list_offset: 0,
            credential_target: None,
            credential: CredentialBuffer::default(),
            credential_revealed: false,
            confirmation_target: None,
            wifi_share: None,
            quit: false,
        }
    }

    pub fn should_quit(&self) -> bool {
        self.quit
    }

    pub fn request_quit(&mut self) {
        self.quit = true;
    }

    pub fn credential_length(&self) -> usize {
        self.credential.0.chars().count()
    }

    pub fn credential_revealed(&self) -> bool {
        self.credential_revealed
    }

    pub fn credential_text(&self) -> &str {
        self.credential.0.as_str()
    }

    pub fn confirmation_target(&self) -> Option<&EntityId> {
        self.confirmation_target.as_ref()
    }

    pub fn wifi_share(&self) -> Option<(&str, &str, Option<&str>)> {
        self.wifi_share.as_ref().map(|share| {
            (
                share.network_name.as_str(),
                share.password.expose(),
                share.qr.as_deref().map(String::as_str),
            )
        })
    }

    pub fn show_wifi_share(
        &mut self,
        id: &WifiNetworkId,
        password: Secret,
        with_qr: bool,
    ) -> Result<(), String> {
        let network = self
            .reducer
            .state
            .wifi
            .networks
            .get(id)
            .ok_or_else(|| "The selected Wi-Fi network disappeared".to_owned())?;
        let qr = if with_qr {
            let payload = wifi_qr_payload(id, password.expose())?;
            let code = qrcode::QrCode::new(payload.as_bytes())
                .map_err(|error| format!("Could not encode Wi-Fi QR code: {error}"))?;
            Some(Zeroizing::new(
                code.render::<qrcode::render::unicode::Dense1x2>()
                    .quiet_zone(true)
                    .build(),
            ))
        } else {
            None
        };
        self.wifi_share = Some(WifiShare {
            network_name: network.display_name.clone(),
            password,
            qr,
        });
        self.overlay = Some(Overlay::WifiShare);
        Ok(())
    }

    pub fn show_diagnostics(&mut self, lines: Vec<String>) {
        self.diagnostics = lines;
        self.overlay = Some(Overlay::Diagnostics);
    }

    pub fn list_offset(&self) -> usize {
        match self.pane {
            Pane::Wifi => self.wifi_list_offset,
            Pane::Bluetooth => self.bluetooth_list_offset,
        }
    }

    pub fn set_rendered_list(&mut self, area: Rect, first_visible_row: usize) {
        match self.pane {
            Pane::Wifi => self.wifi_list_offset = first_visible_row,
            Pane::Bluetooth => self.bluetooth_list_offset = first_visible_row,
        }
        self.set_list_hit_area(area, first_visible_row);
    }

    pub fn set_detail_action_hit_areas(&mut self, areas: Vec<(Rect, EntryAction)>) {
        self.detail_action_hit_areas = areas;
    }

    pub fn entry_actions(&self) -> Vec<EntryAction> {
        let mut actions = Vec::new();
        let has_selection = match self.pane {
            Pane::Wifi => self.selected_wifi().is_some(),
            Pane::Bluetooth => self.reducer.state.bluetooth.selected.is_some(),
        };
        if has_selection {
            actions.push(EntryAction::ToggleConnection);
        }
        match self.pane {
            Pane::Wifi => {
                if self.palette_action_available(PaletteAction::ToggleAutoJoin) {
                    actions.push(EntryAction::ToggleAutoJoin);
                }
                if self.palette_action_available(PaletteAction::ShowWifiPassword) {
                    actions.push(EntryAction::ShowPassword);
                }
                if self.palette_action_available(PaletteAction::ShowWifiQr) {
                    actions.push(EntryAction::ShowQr);
                }
                if self.palette_action_available(PaletteAction::ForgetWifi) {
                    actions.push(EntryAction::Forget);
                }
            }
            Pane::Bluetooth => {
                if self.palette_action_available(PaletteAction::ForgetBluetooth) {
                    actions.push(EntryAction::Forget);
                }
            }
        }
        actions
    }

    pub fn entry_action_label(&self, action: EntryAction) -> String {
        match action {
            EntryAction::ToggleConnection => {
                let connected = match self.pane {
                    Pane::Wifi => self
                        .selected_wifi()
                        .is_some_and(|network| network.state == ConnectionState::Connected),
                    Pane::Bluetooth => self
                        .reducer
                        .state
                        .bluetooth
                        .selected
                        .as_ref()
                        .and_then(|id| self.reducer.state.bluetooth.devices.get(id))
                        .is_some_and(|device| device.state == ConnectionState::Connected),
                };
                format!(
                    "[Enter] {}",
                    if connected { "Disconnect" } else { "Connect" }
                )
            }
            EntryAction::ToggleAutoJoin => format!(
                "[a] {} auto-join",
                if self
                    .selected_wifi()
                    .is_some_and(|network| network.auto_join)
                {
                    "Disable"
                } else {
                    "Enable"
                }
            ),
            EntryAction::ShowPassword => "[p] Show saved password".into(),
            EntryAction::ShowQr => "[r] Show Wi-Fi QR code".into(),
            EntryAction::Forget => "[f] Forget".into(),
        }
    }

    pub fn tick(&mut self, now_ms: u64) -> bool {
        let changed =
            self.reducer.apply(AppEvent::Tick(now_ms)) == crate::domain::ReduceOutcome::Changed;
        changed || self.needs_animation()
    }

    pub fn needs_animation(&self) -> bool {
        !self.reducer.state.operations.is_empty()
            || self
                .reducer
                .state
                .wifi
                .interfaces
                .values()
                .any(|interface| interface.scanning)
            || self
                .reducer
                .state
                .bluetooth
                .adapters
                .values()
                .any(|adapter| adapter.scanning)
    }

    pub fn handle_terminal_event(&mut self, event: Event) -> Option<Intent> {
        match event {
            Event::Key(key) if key.kind != KeyEventKind::Release => self.handle_key(key),
            Event::Mouse(mouse) if self.overlay.is_none() => self.handle_mouse(mouse),
            Event::Mouse(_) => None,
            Event::Resize(_, _) => None,
            _ => None,
        }
    }

    pub fn visible_wifi_ids(&self) -> Vec<WifiNetworkId> {
        let query = self.search.to_lowercase();
        self.reducer
            .state
            .wifi
            .order
            .iter()
            .filter(|id| {
                query.is_empty()
                    || self.reducer.state.wifi.networks[*id]
                        .display_name
                        .to_lowercase()
                        .contains(&query)
            })
            .cloned()
            .collect()
    }

    pub fn visible_bluetooth_ids(&self) -> Vec<BluetoothDeviceId> {
        let query = self.search.to_lowercase();
        self.reducer
            .state
            .bluetooth
            .order
            .iter()
            .filter(|id| {
                let device = &self.reducer.state.bluetooth.devices[*id];
                query.is_empty()
                    || device.name.to_lowercase().contains(&query)
                    || id.address.0.to_lowercase().contains(&query)
            })
            .cloned()
            .collect()
    }

    pub fn filtered_palette_actions(&self) -> Vec<PaletteAction> {
        let query = self.palette_query.to_lowercase();
        PaletteAction::ALL
            .into_iter()
            .filter(|action| {
                self.palette_action_available(*action)
                    && action.label().to_lowercase().contains(&query)
            })
            .collect()
    }

    fn palette_action_available(&self, action: PaletteAction) -> bool {
        match action {
            PaletteAction::ToggleWifi | PaletteAction::ScanWifi => self
                .reducer
                .state
                .wifi
                .selected_interface
                .as_ref()
                .and_then(|id| self.reducer.state.wifi.interfaces.get(id))
                .is_some_and(|interface| {
                    capability_supported(
                        &interface.capabilities,
                        if action == PaletteAction::ToggleWifi {
                            Capability::RadioToggle
                        } else {
                            Capability::Scan
                        },
                    )
                }),
            PaletteAction::ToggleBluetooth | PaletteAction::DiscoverBluetooth => self
                .reducer
                .state
                .bluetooth
                .selected_adapter
                .as_ref()
                .and_then(|id| self.reducer.state.bluetooth.adapters.get(id))
                .is_some_and(|adapter| {
                    capability_supported(
                        &adapter.capabilities,
                        if action == PaletteAction::ToggleBluetooth {
                            Capability::RadioToggle
                        } else {
                            Capability::Scan
                        },
                    )
                }),
            PaletteAction::ToggleAutoJoin | PaletteAction::ForgetWifi => {
                self.selected_wifi().is_some_and(|network| {
                    network.saved
                        && self.selected_wifi_capability(
                            if action == PaletteAction::ToggleAutoJoin {
                                Capability::AutoJoin
                            } else {
                                Capability::Forget
                            },
                        )
                })
            }
            PaletteAction::ShowWifiPassword => self.selected_wifi().is_some_and(|network| {
                network.saved
                    && matches!(
                        network.id.security,
                        WifiSecurity::Personal | WifiSecurity::Wep
                    )
                    && self.selected_wifi_capability(Capability::SecretRetrieval)
            }),
            PaletteAction::ShowWifiQr => self.selected_wifi().is_some_and(|network| {
                network.saved
                    && matches!(
                        network.id.security,
                        WifiSecurity::Open | WifiSecurity::Personal | WifiSecurity::Wep
                    )
                    && (network.id.security == WifiSecurity::Open
                        || self.selected_wifi_capability(Capability::SecretRetrieval))
            }),
            PaletteAction::ForgetBluetooth => self
                .reducer
                .state
                .bluetooth
                .selected
                .as_ref()
                .and_then(|id| self.reducer.state.bluetooth.devices.get(id))
                .is_some_and(|device| {
                    (device.paired || device.trusted)
                        && self
                            .reducer
                            .state
                            .bluetooth
                            .selected_adapter
                            .as_ref()
                            .and_then(|id| self.reducer.state.bluetooth.adapters.get(id))
                            .is_some_and(|adapter| {
                                capability_supported(&adapter.capabilities, Capability::Forget)
                            })
                }),
            _ => true,
        }
    }

    fn selected_wifi(&self) -> Option<&crate::domain::WifiNetwork> {
        self.reducer
            .state
            .wifi
            .selected
            .as_ref()
            .and_then(|id| self.reducer.state.wifi.networks.get(id))
    }

    fn selected_wifi_capability(&self, capability: Capability) -> bool {
        self.reducer
            .state
            .wifi
            .selected_interface
            .as_ref()
            .and_then(|id| self.reducer.state.wifi.interfaces.get(id))
            .is_some_and(|interface| capability_supported(&interface.capabilities, capability))
    }

    pub fn set_list_hit_area(&mut self, area: Rect, first_visible_row: usize) {
        self.list_hit_area = ListHitArea {
            area: Some(area),
            first_visible_row,
        };
    }

    pub fn report_backend_pending(&mut self, intent: Intent, now_ms: u64) {
        self.reducer.state.push_activity(ActivityEntry {
            timestamp_ms: now_ms,
            level: ActivityLevel::Warning,
            message: format!("{intent:?}: backend initialization pending"),
            operation: None,
        });
    }

    pub fn report_runtime_error(&mut self, summary: &str, detail: impl Into<String>, now_ms: u64) {
        self.reducer.state.current_error = Some(UserFacingError {
            category: ErrorCategory::ServiceUnavailable,
            summary: summary.into(),
            detail: detail.into(),
            recovery: vec!["Open diagnostics for service and permission details".into()],
            retryable: true,
            backend: None,
            target: None,
            raw_code: None,
        });
        self.reducer.state.push_activity(ActivityEntry {
            timestamp_ms: now_ms,
            level: ActivityLevel::Error,
            message: summary.into(),
            operation: None,
        });
    }

    pub fn report_user_error(&mut self, error: UserFacingError, now_ms: u64) {
        let summary = error.summary.clone();
        self.reducer.state.current_error = Some(error);
        self.reducer.state.push_activity(ActivityEntry {
            timestamp_ms: now_ms,
            level: ActivityLevel::Error,
            message: summary,
            operation: None,
        });
    }

    fn handle_key(&mut self, key: KeyEvent) -> Option<Intent> {
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
            return Some(Intent::Quit);
        }
        if self.overlay == Some(Overlay::Credential) {
            return self.handle_credential_key(key);
        }
        if self.overlay == Some(Overlay::Confirm) {
            return self.handle_confirmation_key(key);
        }
        if self.overlay == Some(Overlay::WifiShare) {
            if matches!(key.code, KeyCode::Esc | KeyCode::Char('q') | KeyCode::Enter) {
                self.overlay = None;
                self.wifi_share = None;
            }
            return None;
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('p') {
            self.overlay = Some(Overlay::Palette);
            self.palette_query.clear();
            self.palette_selected = 0;
            return None;
        }

        match self.overlay {
            Some(Overlay::Palette) => return self.handle_palette_key(key),
            Some(Overlay::Search) => return self.handle_search_key(key),
            Some(Overlay::Credential | Overlay::Confirm | Overlay::WifiShare) => {
                unreachable!("interactive overlays handled above")
            }
            Some(Overlay::Help | Overlay::Activity | Overlay::Diagnostics | Overlay::Error) => {
                if matches!(key.code, KeyCode::Esc | KeyCode::Char('q') | KeyCode::Enter) {
                    self.overlay = None;
                }
                return None;
            }
            None => {}
        }

        match key.code {
            KeyCode::Char('q') => Some(Intent::Quit),
            KeyCode::Esc => {
                if self.reducer.state.current_error.is_some() {
                    self.reducer.apply(AppEvent::DismissError);
                } else if !self.search.is_empty() {
                    self.search.clear();
                }
                None
            }
            KeyCode::Tab => {
                self.pane = match self.pane {
                    Pane::Wifi => Pane::Bluetooth,
                    Pane::Bluetooth => Pane::Wifi,
                };
                None
            }
            KeyCode::Char('1') => {
                self.pane = Pane::Wifi;
                None
            }
            KeyCode::Char('2') => {
                self.pane = Pane::Bluetooth;
                None
            }
            KeyCode::Char('?') => {
                self.overlay = Some(Overlay::Help);
                None
            }
            KeyCode::Char('l') => {
                self.overlay = Some(Overlay::Activity);
                None
            }
            KeyCode::Char('e') if self.reducer.state.current_error.is_some() => {
                self.overlay = Some(Overlay::Error);
                None
            }
            KeyCode::Char('/') => {
                self.overlay = Some(Overlay::Search);
                None
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.move_selection(1);
                None
            }
            KeyCode::Up | KeyCode::Char('k') => {
                self.move_selection(-1);
                None
            }
            KeyCode::Home | KeyCode::Char('g') => {
                self.select_edge(false);
                None
            }
            KeyCode::End | KeyCode::Char('G') => {
                self.select_edge(true);
                None
            }
            KeyCode::Enter => self.run_entry_action(EntryAction::ToggleConnection),
            KeyCode::Char('a') if self.entry_actions().contains(&EntryAction::ToggleAutoJoin) => {
                self.run_entry_action(EntryAction::ToggleAutoJoin)
            }
            KeyCode::Char('p') if self.entry_actions().contains(&EntryAction::ShowPassword) => {
                self.run_entry_action(EntryAction::ShowPassword)
            }
            KeyCode::Char('r') if self.entry_actions().contains(&EntryAction::ShowQr) => {
                self.run_entry_action(EntryAction::ShowQr)
            }
            KeyCode::Char('f') if self.entry_actions().contains(&EntryAction::Forget) => {
                self.run_entry_action(EntryAction::Forget)
            }
            KeyCode::Char('s') => Some(match self.pane {
                Pane::Wifi => Intent::ScanWifi,
                Pane::Bluetooth => Intent::ToggleBluetoothDiscovery,
            }),
            _ => None,
        }
    }

    fn handle_palette_key(&mut self, key: KeyEvent) -> Option<Intent> {
        match key.code {
            KeyCode::Esc => {
                self.overlay = None;
                None
            }
            KeyCode::Backspace => {
                self.palette_query.pop();
                self.palette_selected = 0;
                None
            }
            KeyCode::Char(character) => {
                self.palette_query.push(character);
                self.palette_selected = 0;
                None
            }
            KeyCode::Down => {
                let length = self.filtered_palette_actions().len();
                if length > 0 {
                    self.palette_selected = (self.palette_selected + 1) % length;
                }
                None
            }
            KeyCode::Up => {
                let length = self.filtered_palette_actions().len();
                if length > 0 {
                    self.palette_selected = (self.palette_selected + length - 1) % length;
                }
                None
            }
            KeyCode::Enter => {
                let action = self
                    .filtered_palette_actions()
                    .get(self.palette_selected)
                    .copied();
                self.overlay = None;
                action.and_then(|action| self.run_palette_action(action))
            }
            _ => None,
        }
    }

    fn handle_search_key(&mut self, key: KeyEvent) -> Option<Intent> {
        match key.code {
            KeyCode::Esc | KeyCode::Enter => self.overlay = None,
            KeyCode::Backspace => {
                self.search.pop();
                self.ensure_visible_selection();
            }
            KeyCode::Char(character) => {
                self.search.push(character);
                self.ensure_visible_selection();
            }
            _ => {}
        }
        None
    }

    fn handle_credential_key(&mut self, key: KeyEvent) -> Option<Intent> {
        if (key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('r'))
            || key.code == KeyCode::F(2)
        {
            self.credential_revealed = !self.credential_revealed;
            return None;
        }
        match key.code {
            KeyCode::Esc => {
                self.overlay = None;
                self.credential_target = None;
                self.credential.0.clear();
                self.credential_revealed = false;
                None
            }
            KeyCode::Backspace => {
                self.credential.0.pop();
                None
            }
            KeyCode::Enter if !self.credential.0.is_empty() => {
                let target = self.credential_target.take()?;
                let credential = std::mem::take(&mut self.credential.0);
                self.overlay = None;
                self.credential_revealed = false;
                Some(Intent::SetConnection {
                    target,
                    desired: DesiredState::Connected,
                    credential: Some(Secret::new(credential.to_string())),
                })
            }
            KeyCode::Char(character)
                if !key
                    .modifiers
                    .intersects(KeyModifiers::CONTROL | KeyModifiers::ALT) =>
            {
                self.credential.0.push(character);
                None
            }
            _ => None,
        }
    }

    fn handle_confirmation_key(&mut self, key: KeyEvent) -> Option<Intent> {
        match key.code {
            KeyCode::Enter | KeyCode::Char('y') => {
                let target = self.confirmation_target.take()?;
                self.overlay = None;
                Some(Intent::Forget(target))
            }
            KeyCode::Esc | KeyCode::Char('n') | KeyCode::Char('q') => {
                self.confirmation_target = None;
                self.overlay = None;
                None
            }
            _ => None,
        }
    }

    fn run_palette_action(&mut self, action: PaletteAction) -> Option<Intent> {
        match action {
            PaletteAction::ToggleWifi => Some(Intent::ToggleWifiRadio),
            PaletteAction::ScanWifi => Some(Intent::ScanWifi),
            PaletteAction::ToggleBluetooth => Some(Intent::ToggleBluetoothRadio),
            PaletteAction::DiscoverBluetooth => Some(Intent::ToggleBluetoothDiscovery),
            PaletteAction::Diagnostics => Some(Intent::OpenDiagnostics),
            PaletteAction::ToggleAutoJoin => {
                let network = self.selected_wifi()?;
                Some(Intent::SetWifiAutoJoin {
                    id: network.id.clone(),
                    enabled: !network.auto_join,
                })
            }
            PaletteAction::ForgetWifi => {
                let id = self.reducer.state.wifi.selected.clone()?;
                self.confirmation_target = Some(EntityId::Wifi(id));
                self.overlay = Some(Overlay::Confirm);
                None
            }
            PaletteAction::ShowWifiPassword => self
                .reducer
                .state
                .wifi
                .selected
                .clone()
                .map(|id| Intent::ShowWifiSecret { id, qr: false }),
            PaletteAction::ShowWifiQr => self
                .reducer
                .state
                .wifi
                .selected
                .clone()
                .map(|id| Intent::ShowWifiSecret { id, qr: true }),
            PaletteAction::ForgetBluetooth => {
                let id = self.reducer.state.bluetooth.selected.clone()?;
                self.confirmation_target = Some(EntityId::Bluetooth(id));
                self.overlay = Some(Overlay::Confirm);
                None
            }
            PaletteAction::Activity => {
                self.overlay = Some(Overlay::Activity);
                None
            }
            PaletteAction::Help => {
                self.overlay = Some(Overlay::Help);
                None
            }
            PaletteAction::Quit => Some(Intent::Quit),
        }
    }

    fn run_entry_action(&mut self, action: EntryAction) -> Option<Intent> {
        match action {
            EntryAction::ToggleConnection => self.connection_intent(),
            EntryAction::ToggleAutoJoin => {
                let network = self.selected_wifi()?;
                Some(Intent::SetWifiAutoJoin {
                    id: network.id.clone(),
                    enabled: !network.auto_join,
                })
            }
            EntryAction::ShowPassword => self
                .reducer
                .state
                .wifi
                .selected
                .clone()
                .map(|id| Intent::ShowWifiSecret { id, qr: false }),
            EntryAction::ShowQr => self
                .reducer
                .state
                .wifi
                .selected
                .clone()
                .map(|id| Intent::ShowWifiSecret { id, qr: true }),
            EntryAction::Forget => {
                let target = match self.pane {
                    Pane::Wifi => self.reducer.state.wifi.selected.clone().map(EntityId::Wifi),
                    Pane::Bluetooth => self
                        .reducer
                        .state
                        .bluetooth
                        .selected
                        .clone()
                        .map(EntityId::Bluetooth),
                }?;
                self.confirmation_target = Some(target);
                self.overlay = Some(Overlay::Confirm);
                None
            }
        }
    }

    fn connection_intent(&mut self) -> Option<Intent> {
        let target = match self.pane {
            Pane::Wifi => self.reducer.state.wifi.selected.clone().map(EntityId::Wifi),
            Pane::Bluetooth => self
                .reducer
                .state
                .bluetooth
                .selected
                .clone()
                .map(EntityId::Bluetooth),
        }?;

        if let Some(operation) = self.reducer.state.active_operation(&target) {
            return Some(Intent::Cancel(operation.id));
        }

        let connected = match &target {
            EntityId::Wifi(id) => {
                self.reducer.state.wifi.networks[id].state == ConnectionState::Connected
            }
            EntityId::Bluetooth(id) => {
                self.reducer.state.bluetooth.devices[id].state == ConnectionState::Connected
            }
            _ => false,
        };
        if !connected {
            if let EntityId::Wifi(id) = &target {
                let network = &self.reducer.state.wifi.networks[id];
                if !network.saved
                    && matches!(id.security, WifiSecurity::Personal | WifiSecurity::Wep)
                {
                    self.credential_target = Some(target);
                    self.credential.0.clear();
                    self.credential_revealed = false;
                    self.overlay = Some(Overlay::Credential);
                    return None;
                }
            }
        }
        Some(Intent::SetConnection {
            target,
            desired: if connected {
                DesiredState::Disconnected
            } else {
                DesiredState::Connected
            },
            credential: None,
        })
    }

    fn move_selection(&mut self, delta: isize) {
        match self.pane {
            Pane::Wifi => {
                let visible = self.visible_wifi_ids();
                let selected =
                    move_in_list(&visible, self.reducer.state.wifi.selected.as_ref(), delta);
                self.reducer.apply(AppEvent::SelectWifi(selected));
            }
            Pane::Bluetooth => {
                let visible = self.visible_bluetooth_ids();
                let selected = move_in_list(
                    &visible,
                    self.reducer.state.bluetooth.selected.as_ref(),
                    delta,
                );
                self.reducer.apply(AppEvent::SelectBluetooth(selected));
            }
        }
    }

    fn select_edge(&mut self, end: bool) {
        match self.pane {
            Pane::Wifi => {
                let visible = self.visible_wifi_ids();
                let selected = if end { visible.last() } else { visible.first() }.cloned();
                self.reducer.apply(AppEvent::SelectWifi(selected));
            }
            Pane::Bluetooth => {
                let visible = self.visible_bluetooth_ids();
                let selected = if end { visible.last() } else { visible.first() }.cloned();
                self.reducer.apply(AppEvent::SelectBluetooth(selected));
            }
        }
    }

    fn ensure_visible_selection(&mut self) {
        match self.pane {
            Pane::Wifi => {
                let visible = self.visible_wifi_ids();
                if self
                    .reducer
                    .state
                    .wifi
                    .selected
                    .as_ref()
                    .is_none_or(|id| !visible.contains(id))
                {
                    self.reducer
                        .apply(AppEvent::SelectWifi(visible.first().cloned()));
                }
            }
            Pane::Bluetooth => {
                let visible = self.visible_bluetooth_ids();
                if self
                    .reducer
                    .state
                    .bluetooth
                    .selected
                    .as_ref()
                    .is_none_or(|id| !visible.contains(id))
                {
                    self.reducer
                        .apply(AppEvent::SelectBluetooth(visible.first().cloned()));
                }
            }
        }
    }

    fn handle_mouse(&mut self, mouse: MouseEvent) -> Option<Intent> {
        match mouse.kind {
            MouseEventKind::ScrollDown => {
                self.move_selection(1);
                None
            }
            MouseEventKind::ScrollUp => {
                self.move_selection(-1);
                None
            }
            MouseEventKind::Down(MouseButton::Left) => {
                if let Some((_, action)) = self.detail_action_hit_areas.iter().find(|(area, _)| {
                    mouse.column >= area.x
                        && mouse.column < area.right()
                        && mouse.row >= area.y
                        && mouse.row < area.bottom()
                }) {
                    return self.run_entry_action(*action);
                }
                let area = self.list_hit_area.area?;
                if mouse.column < area.x
                    || mouse.column >= area.right()
                    || mouse.row < area.y
                    || mouse.row >= area.bottom()
                {
                    return None;
                }
                let row = self.list_hit_area.first_visible_row
                    + usize::from(mouse.row.saturating_sub(area.y));
                match self.pane {
                    Pane::Wifi => {
                        let selected = self.visible_wifi_ids().get(row).cloned();
                        self.reducer.apply(AppEvent::SelectWifi(selected));
                    }
                    Pane::Bluetooth => {
                        let selected = self.visible_bluetooth_ids().get(row).cloned();
                        self.reducer.apply(AppEvent::SelectBluetooth(selected));
                    }
                }
                None
            }
            _ => None,
        }
    }
}

fn capability_supported(
    capabilities: &std::collections::BTreeMap<Capability, CapabilityState>,
    capability: Capability,
) -> bool {
    capabilities.get(&capability) == Some(&CapabilityState::Supported)
}

fn wifi_qr_payload(id: &WifiNetworkId, password: &str) -> Result<Zeroizing<String>, String> {
    let ssid = std::str::from_utf8(&id.ssid.0)
        .map_err(|_| "QR sharing requires a UTF-8 Wi-Fi name".to_owned())?;
    let security = match id.security {
        WifiSecurity::Open => "nopass",
        WifiSecurity::Wep => "WEP",
        WifiSecurity::Personal => "WPA",
        WifiSecurity::Enterprise => {
            return Err("Enterprise Wi-Fi needs identity and EAP settings, so a password-only QR code would be incomplete".into())
        }
        WifiSecurity::Unknown(_) => {
            return Err("The Wi-Fi security type is unknown, so a safe QR code cannot be generated".into())
        }
    };
    let ssid = escape_wifi_qr_field(ssid);
    if id.security == WifiSecurity::Open {
        Ok(Zeroizing::new(format!("WIFI:T:{security};S:{ssid};;")))
    } else {
        Ok(Zeroizing::new(format!(
            "WIFI:T:{security};S:{ssid};P:{};;",
            escape_wifi_qr_field(password)
        )))
    }
}

fn escape_wifi_qr_field(value: &str) -> String {
    let mut escaped = String::with_capacity(value.len());
    for character in value.chars() {
        if matches!(character, '\\' | ';' | ',' | ':' | '"') {
            escaped.push('\\');
        }
        escaped.push(character);
    }
    escaped
}

fn move_in_list<T: Clone + PartialEq>(
    items: &[T],
    selected: Option<&T>,
    delta: isize,
) -> Option<T> {
    if items.is_empty() {
        return None;
    }
    let current = selected
        .and_then(|selected| items.iter().position(|item| item == selected))
        .unwrap_or(0);
    let next = if delta < 0 {
        current
            .checked_sub(delta.unsigned_abs())
            .unwrap_or(items.len() - 1)
    } else {
        (current + delta as usize) % items.len()
    };
    items.get(next).cloned()
}

#[cfg(test)]
mod tests {
    use crossterm::event::{KeyEvent, KeyEventState};

    use super::*;
    use crate::domain::{
        BackendEvent, BackendKind, BackendPayload, Connectivity, InterfaceId, IpAddressInfo, Ssid,
        WifiInterface, WifiNetwork, WifiNetworkId, WifiSecurity, WifiSnapshot,
    };

    fn key(code: KeyCode) -> Event {
        Event::Key(KeyEvent {
            code,
            modifiers: KeyModifiers::NONE,
            kind: KeyEventKind::Press,
            state: KeyEventState::NONE,
        })
    }

    fn application_with_network(state: ConnectionState) -> Application {
        let mut app = Application::new();
        let id = WifiNetworkId {
            interface: InterfaceId("wlan0".into()),
            ssid: Ssid(b"Home".to_vec()),
            security: WifiSecurity::Personal,
        };
        app.reducer.apply(AppEvent::Backend(BackendEvent {
            backend: BackendKind::NetworkManager,
            epoch: 1,
            revision: 1,
            observed_at_ms: 1,
            payload: BackendPayload::WifiSnapshot(WifiSnapshot {
                interfaces: vec![WifiInterface {
                    id: InterfaceId("wlan0".into()),
                    backend: BackendKind::NetworkManager,
                    powered: true,
                    scanning: false,
                    last_scan_ms: Some(1),
                    addresses: vec![IpAddressInfo {
                        address: "192.0.2.8".into(),
                        prefix_len: 24,
                        netmask: "255.255.255.0".into(),
                    }],
                    capabilities: std::collections::BTreeMap::from([
                        (Capability::AutoJoin, CapabilityState::Supported),
                        (Capability::Forget, CapabilityState::Supported),
                        (Capability::SecretRetrieval, CapabilityState::Supported),
                    ]),
                }],
                networks: vec![WifiNetwork {
                    id,
                    display_name: "Home".into(),
                    signal: 80,
                    state,
                    connectivity: Connectivity::Internet,
                    saved: true,
                    auto_join: true,
                    bss_count: 1,
                    active_bssid: None,
                    present: true,
                    last_seen_ms: 1,
                }],
            }),
        }));
        app
    }

    #[test]
    fn enter_disconnects_an_already_connected_network() {
        let mut app = application_with_network(ConnectionState::Connected);
        let intent = app.handle_terminal_event(key(KeyCode::Enter)).unwrap();
        assert!(matches!(
            intent,
            Intent::SetConnection {
                desired: DesiredState::Disconnected,
                ..
            }
        ));
    }

    #[test]
    fn command_palette_filters_and_dispatches() {
        let mut app = Application::new();
        app.handle_terminal_event(Event::Key(KeyEvent::new(
            KeyCode::Char('p'),
            KeyModifiers::CONTROL,
        )));
        for character in "diagnostics".chars() {
            app.handle_terminal_event(key(KeyCode::Char(character)));
        }
        assert_eq!(
            app.filtered_palette_actions(),
            vec![PaletteAction::Diagnostics]
        );
        assert!(matches!(
            app.handle_terminal_event(key(KeyCode::Enter)),
            Some(Intent::OpenDiagnostics)
        ));
    }

    #[test]
    fn search_keeps_selection_in_visible_results() {
        let mut app = application_with_network(ConnectionState::Disconnected);
        app.overlay = Some(Overlay::Search);
        app.handle_terminal_event(key(KeyCode::Char('x')));
        assert_eq!(app.reducer.state.wifi.selected, None);
    }

    #[test]
    fn runtime_errors_persist_until_dismissed() {
        let mut app = Application::new();
        app.report_runtime_error("No service", "NetworkManager is unavailable", 5);
        app.handle_terminal_event(key(KeyCode::Esc));
        assert!(app.reducer.state.current_error.is_none());
    }

    #[test]
    fn empty_palette_navigation_is_safe() {
        let mut app = Application::new();
        app.overlay = Some(Overlay::Palette);
        app.palette_query = "no action has this name".into();
        assert_eq!(app.filtered_palette_actions(), Vec::new());
        assert!(app.handle_terminal_event(key(KeyCode::Up)).is_none());
    }

    #[test]
    fn new_secured_network_prompts_and_never_debug_prints_the_password() {
        let mut app = application_with_network(ConnectionState::Disconnected);
        let selected = app.reducer.state.wifi.selected.clone().unwrap();
        app.reducer
            .state
            .wifi
            .networks
            .get_mut(&selected)
            .unwrap()
            .saved = false;

        assert!(app.handle_terminal_event(key(KeyCode::Enter)).is_none());
        assert_eq!(app.overlay, Some(Overlay::Credential));
        for character in "not-for-logs".chars() {
            app.handle_terminal_event(key(KeyCode::Char(character)));
        }
        app.handle_terminal_event(key(KeyCode::F(2)));
        assert!(app.credential_revealed());
        assert_eq!(app.credential_text(), "not-for-logs");
        let intent = app.handle_terminal_event(key(KeyCode::Enter));
        let debug = format!("{intent:?}");
        assert!(matches!(
            intent,
            Some(Intent::SetConnection {
                credential: Some(_),
                ..
            })
        ));
        assert!(!debug.contains("not-for-logs"));
    }

    #[test]
    fn wifi_qr_payload_escapes_reserved_characters() {
        let id = WifiNetworkId {
            interface: InterfaceId("wlan0".into()),
            ssid: Ssid(b"guest;wifi".to_vec()),
            security: WifiSecurity::Personal,
        };
        let payload = wifi_qr_payload(&id, "a:b\\c").unwrap();
        assert_eq!(payload.as_str(), "WIFI:T:WPA;S:guest\\;wifi;P:a\\:b\\\\c;;");

        let open = WifiNetworkId {
            security: WifiSecurity::Open,
            ..id
        };
        assert_eq!(
            wifi_qr_payload(&open, "").unwrap().as_str(),
            "WIFI:T:nopass;S:guest\\;wifi;;"
        );
    }

    #[test]
    fn wifi_share_overlay_clears_sensitive_material_when_closed() {
        let mut app = application_with_network(ConnectionState::Connected);
        let id = app.reducer.state.wifi.selected.clone().unwrap();
        app.show_wifi_share(&id, Secret::new("private-password".into()), true)
            .unwrap();
        assert_eq!(app.overlay, Some(Overlay::WifiShare));
        assert!(app.wifi_share().unwrap().2.is_some());
        assert!(!format!("{app:?}").contains("private-password"));

        app.handle_terminal_event(key(KeyCode::Esc));
        assert_eq!(app.overlay, None);
        assert!(app.wifi_share().is_none());
    }

    #[test]
    fn forget_requires_confirmation() {
        let mut app = application_with_network(ConnectionState::Disconnected);
        let id = app.reducer.state.wifi.selected.clone().unwrap();
        app.confirmation_target = Some(EntityId::Wifi(id.clone()));
        app.overlay = Some(Overlay::Confirm);

        assert!(matches!(
            app.handle_terminal_event(key(KeyCode::Char('y'))),
            Some(Intent::Forget(EntityId::Wifi(confirmed))) if confirmed == id
        ));
        assert_eq!(app.overlay, None);
    }

    #[test]
    fn mouse_click_uses_the_rendered_scroll_offset() {
        let mut app = application_with_network(ConnectionState::Disconnected);
        let template = app
            .reducer
            .state
            .wifi
            .networks
            .values()
            .next()
            .unwrap()
            .clone();
        let networks = (0..12)
            .map(|index| {
                let mut network = template.clone();
                network.id.ssid = Ssid(format!("network-{index:02}").into_bytes());
                network.display_name = network.id.ssid.display();
                network
            })
            .collect();
        app.reducer.apply(AppEvent::Backend(BackendEvent {
            backend: BackendKind::NetworkManager,
            epoch: 1,
            revision: 2,
            observed_at_ms: 2,
            payload: BackendPayload::WifiSnapshot(WifiSnapshot {
                interfaces: Vec::new(),
                networks,
            }),
        }));
        let expected = app.visible_wifi_ids()[6].clone();
        app.set_rendered_list(Rect::new(2, 4, 20, 3), 6);
        app.handle_terminal_event(Event::Mouse(MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: 2,
            row: 4,
            modifiers: KeyModifiers::NONE,
        }));
        assert_eq!(app.reducer.state.wifi.selected, Some(expected));
    }

    #[test]
    fn right_pane_action_click_dispatches_the_displayed_action() {
        let mut app = application_with_network(ConnectionState::Connected);
        app.set_detail_action_hit_areas(vec![(
            Rect::new(80, 10, 20, 1),
            EntryAction::ToggleAutoJoin,
        )]);

        let intent = app.handle_terminal_event(Event::Mouse(MouseEvent {
            kind: MouseEventKind::Down(MouseButton::Left),
            column: 82,
            row: 10,
            modifiers: KeyModifiers::NONE,
        }));

        assert!(matches!(
            intent,
            Some(Intent::SetWifiAutoJoin { enabled: false, .. })
        ));
    }

    #[test]
    fn enter_on_an_in_flight_connection_requests_reversal() {
        let mut app = application_with_network(ConnectionState::Disconnected);
        let target = EntityId::Wifi(app.reducer.state.wifi.selected.clone().unwrap());
        app.reducer
            .apply(AppEvent::OperationStarted(crate::domain::Operation {
                id: OperationId(9),
                backend: BackendKind::NetworkManager,
                target,
                desired: DesiredState::Connected,
                phase: crate::domain::OperationPhase::Queued,
                started_at_ms: 0,
                deadline_ms: 100,
                backend_epoch: 1,
            }));
        assert!(matches!(
            app.handle_terminal_event(key(KeyCode::Enter)),
            Some(Intent::Cancel(OperationId(9)))
        ));
    }
}
