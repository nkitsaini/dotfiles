mod nm;
mod bt;

use std::error::Error;
use std::io;
use std::time::Duration;
use tokio::sync::mpsc;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, KeyCode, KeyEvent, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Row, Table, TableState, Tabs},
    Frame, Terminal,
};

use nm::{NmClient, WifiApInfo};
use bt::{BtClient, BtDeviceInfo};
use bluer::Address;

// Background Commands
#[derive(Debug)]
pub enum AppCmd {
    WifiScan,
    WifiConnect {
        ap_path: String,
        ssid: String,
        password: Option<String>,
    },
    WifiDisconnect,
    BtScanToggle,
    BtConnect { address: Address, name: String },
    BtDisconnect { address: Address, name: String },
    BtPair { address: Address, name: String },
    BtTrust { address: Address, name: String, trust: bool },
    BtBlock { address: Address, name: String, block: bool },
    BtRemove { address: Address, name: String },
}

// Background Events
#[derive(Debug, Clone)]
pub enum AppEvent {
    WifiState {
        scanning: bool,
        interface: String,
        active_ssid: Option<String>,
        access_points: Vec<WifiApInfo>,
    },
    BtState {
        scanning: bool,
        devices: Vec<BtDeviceInfo>,
    },
    Status(String),
    Error(String),
}

// App tabs
#[derive(Debug, Copy, Clone, PartialEq)]
enum Tab {
    Wifi,
    Bluetooth,
}

struct PasswordPrompt {
    ssid: String,
    ap_path: String,
    input: String,
}

// GUI/TUI State
struct App {
    active_tab: Tab,
    running: bool,
    
    // Wi-Fi State
    wifi_scanning: bool,
    wifi_interface: String,
    wifi_active_ssid: Option<String>,
    wifi_aps: Vec<WifiApInfo>,
    wifi_table_state: TableState,
    password_prompt: Option<PasswordPrompt>,
    
    // Bluetooth State
    bt_scanning: bool,
    bt_devices: Vec<BtDeviceInfo>,
    bt_table_state: TableState,
    
    // Messages
    status_message: Option<(String, bool)>, // (message, is_error)
    status_timer: u32,                       // ticks until cleared
    
    tick_count: u32,
}

impl App {
    fn new() -> Self {
        let mut wifi_state = TableState::default();
        wifi_state.select(Some(0));
        let mut bt_state = TableState::default();
        bt_state.select(Some(0));
        
        Self {
            active_tab: Tab::Wifi,
            running: true,
            wifi_scanning: false,
            wifi_interface: "unknown".to_string(),
            wifi_active_ssid: None,
            wifi_aps: Vec::new(),
            wifi_table_state: wifi_state,
            password_prompt: None,
            bt_scanning: false,
            bt_devices: Vec::new(),
            bt_table_state: bt_state,
            status_message: None,
            status_timer: 0,
            tick_count: 0,
        }
    }

    fn select_next_wifi(&mut self) {
        if self.wifi_aps.is_empty() {
            return;
        }
        let i = match self.wifi_table_state.selected() {
            Some(i) => {
                if i >= self.wifi_aps.len() - 1 {
                    0
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.wifi_table_state.select(Some(i));
    }

    fn select_prev_wifi(&mut self) {
        if self.wifi_aps.is_empty() {
            return;
        }
        let i = match self.wifi_table_state.selected() {
            Some(i) => {
                if i == 0 {
                    self.wifi_aps.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.wifi_table_state.select(Some(i));
    }

    fn select_next_bt(&mut self) {
        if self.bt_devices.is_empty() {
            return;
        }
        let i = match self.bt_table_state.selected() {
            Some(i) => {
                if i >= self.bt_devices.len() - 1 {
                    0
                } else {
                    i + 1
                }
            }
            None => 0,
        };
        self.bt_table_state.select(Some(i));
    }

    fn select_prev_bt(&mut self) {
        if self.bt_devices.is_empty() {
            return;
        }
        let i = match self.bt_table_state.selected() {
            Some(i) => {
                if i == 0 {
                    self.bt_devices.len() - 1
                } else {
                    i - 1
                }
            }
            None => 0,
        };
        self.bt_table_state.select(Some(i));
    }

    fn show_status(&mut self, msg: String, is_error: bool) {
        self.status_message = Some((msg, is_error));
        self.status_timer = 30; // ~6 seconds (at 200ms tick rate)
    }

    fn tick(&mut self) {
        self.tick_count += 1;
        if self.status_timer > 0 {
            self.status_timer -= 1;
            if self.status_timer == 0 {
                self.status_message = None;
            }
        }
    }
}

// Terminal Cleanup Guard
struct TerminalGuard;
impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, DisableMouseCapture);
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    // Channel for events from worker to main thread
    let (event_tx, mut event_rx) = mpsc::channel(100);
    // Channel for commands from main thread to worker
    let (cmd_tx, cmd_rx) = mpsc::channel(100);

    // Spawn Background DBus Worker
    tokio::spawn(async move {
        run_worker(cmd_rx, event_tx).await;
    });

    // Initialize Terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;
    let _guard = TerminalGuard; // Will restore terminal settings on exit/panic

    // Spawn keyboard event thread
    let (key_tx, mut key_rx) = mpsc::channel(100);
    tokio::spawn(async move {
        loop {
            if event::poll(Duration::from_millis(50)).unwrap() {
                if let Ok(event::Event::Key(key)) = event::read() {
                    // Only send Press events (avoid double trigger on Windows/some terminals)
                    if key.kind == event::KeyEventKind::Press || key.kind == event::KeyEventKind::Repeat {
                        if key_tx.send(key).await.is_err() {
                            break;
                        }
                    }
                }
            }
        }
    });

    // Trigger initial scans
    let _ = cmd_tx.send(AppCmd::WifiScan).await;

    let mut app = App::new();
    let mut interval = tokio::time::interval(Duration::from_millis(200));

    while app.running {
        tokio::select! {
            _ = interval.tick() => {
                app.tick();
                terminal.draw(|f| ui_draw(f, &mut app))?;
            }
            
            Some(event) = event_rx.recv() => {
                match event {
                    AppEvent::WifiState { scanning, interface, active_ssid, access_points } => {
                        app.wifi_scanning = scanning;
                        app.wifi_interface = interface;
                        app.wifi_active_ssid = active_ssid;
                        
                        // Stable Wifi AP update: preserve seen order, append new ones at the end
                        let mut updated_wifi_aps = Vec::new();
                        for old_ap in &app.wifi_aps {
                            if let Some(new_ap) = access_points.iter().find(|ap| ap.ssid == old_ap.ssid) {
                                updated_wifi_aps.push(new_ap.clone());
                            }
                        }
                        for new_ap in access_points {
                            if !updated_wifi_aps.iter().any(|ap| ap.ssid == new_ap.ssid) {
                                updated_wifi_aps.push(new_ap);
                            }
                        }
                        app.wifi_aps = updated_wifi_aps;
                        
                        // Move active wifi to the top of the list stably
                        app.wifi_aps.sort_by_key(|ap| !ap.is_active);

                        // Ensure selection is valid
                        if let Some(sel) = app.wifi_table_state.selected() {
                            if sel >= app.wifi_aps.len() && !app.wifi_aps.is_empty() {
                                app.wifi_table_state.select(Some(app.wifi_aps.len() - 1));
                            }
                        }
                    }
                    AppEvent::BtState { scanning, devices } => {
                        app.bt_scanning = scanning;
                        
                        // Stable Bluetooth devices update: preserve order, append new ones at the end
                        let mut updated_bt_devices = Vec::new();
                        for old_dev in &app.bt_devices {
                            if let Some(new_dev) = devices.iter().find(|d| d.address == old_dev.address) {
                                updated_bt_devices.push(new_dev.clone());
                            }
                        }
                        for new_dev in devices {
                            if !updated_bt_devices.iter().any(|d| d.address == new_dev.address) {
                                updated_bt_devices.push(new_dev);
                            }
                        }
                        app.bt_devices = updated_bt_devices;
                        
                        // Move connected devices first, then paired, keeping stable order for the rest
                        app.bt_devices.sort_by(|a, b| {
                            if a.is_connected != b.is_connected {
                                b.is_connected.cmp(&a.is_connected)
                            } else if a.is_paired != b.is_paired {
                                b.is_paired.cmp(&a.is_paired)
                            } else {
                                std::cmp::Ordering::Equal
                            }
                        });

                        // Ensure selection is valid
                        if let Some(sel) = app.bt_table_state.selected() {
                            if sel >= app.bt_devices.len() && !app.bt_devices.is_empty() {
                                app.bt_table_state.select(Some(app.bt_devices.len() - 1));
                            }
                        }
                    }
                    AppEvent::Status(msg) => {
                        app.show_status(msg, false);
                    }
                    AppEvent::Error(msg) => {
                        app.show_status(msg, true);
                    }
                }
                terminal.draw(|f| ui_draw(f, &mut app))?;
            }
            
            Some(key) = key_rx.recv() => {
                handle_key(key, &mut app, &cmd_tx).await?;
                terminal.draw(|f| ui_draw(f, &mut app))?;
            }
        }
    }

    // Explicitly restore terminal and exit the process immediately
    drop(_guard);
    std::process::exit(0);
}

// Background Worker Main Loop
async fn run_worker(mut cmd_rx: mpsc::Receiver<AppCmd>, event_tx: mpsc::Sender<AppEvent>) {
    let nm = match NmClient::new().await {
        Ok(c) => Some(c),
        Err(e) => {
            let _ = event_tx.send(AppEvent::Error(format!("NetworkManager error: {}", e))).await;
            None
        }
    };

    let bt = match BtClient::new().await {
        Ok(c) => Some(c),
        Err(e) => {
            let _ = event_tx.send(AppEvent::Error(format!("Bluetooth (BlueZ) error: {}", e))).await;
            None
        }
    };

    // Find Wifi device path
    let wifi_dev_path = if let Some(ref nm_client) = nm {
        match nm_client.find_wifi_device().await {
            Ok(p) => p,
            Err(e) => {
                let _ = event_tx.send(AppEvent::Error(format!("Failed to find Wi-Fi device: {}", e))).await;
                None
            }
        }
    } else {
        None
    };

    // Initial status report
    let mut wifi_interface = "unknown".to_string();
    if let (Some(ref nm_client), Some(ref dev_path)) = (&nm, &wifi_dev_path) {
        if let Ok(iface) = nm_client.get_wifi_interface_name(dev_path).await {
            wifi_interface = iface;
        }
    }

    // Set up periodic update interval (2 seconds)
    let mut update_tick = tokio::time::interval(Duration::from_secs(2));
    
    // Local copy of states to poll
    let mut bt_scanning = false;
    let mut wifi_scan_deadline: Option<tokio::time::Instant> = None;
    let mut bt_discovery_stream: Option<std::pin::Pin<Box<dyn futures_util::Stream<Item = bluer::AdapterEvent> + Send>>> = None;

    loop {
        tokio::select! {
            _ = update_tick.tick() => {
                // Poll Wi-Fi State
                if let (Some(ref nm_client), Some(ref dev_path)) = (&nm, &wifi_dev_path) {
                    let active_ssid = nm_client.get_active_ssid(dev_path).await.ok().flatten();
                    let is_wifi_scanning = wifi_scan_deadline.map(|d| tokio::time::Instant::now() < d).unwrap_or(false);
                    if let Ok(aps) = nm_client.list_wifi_aps(dev_path).await {
                        let _ = event_tx.send(AppEvent::WifiState {
                            scanning: is_wifi_scanning,
                            interface: wifi_interface.clone(),
                            active_ssid,
                            access_points: aps,
                        }).await;
                    }
                }
                
                // Poll Bluetooth State
                if let Some(ref bt_client) = bt {
                    if let Ok(scanning) = bt_client.is_scanning().await {
                        bt_scanning = scanning;
                    }
                    if let Ok(devices) = bt_client.list_devices().await {
                        let _ = event_tx.send(AppEvent::BtState {
                            scanning: bt_scanning,
                            devices,
                        }).await;
                    }
                }
            }
            
            Some(cmd) = cmd_rx.recv() => {
                match cmd {
                    AppCmd::WifiScan => {
                        if let (Some(ref nm_client), Some(ref dev_path)) = (&nm, &wifi_dev_path) {
                            wifi_scan_deadline = Some(tokio::time::Instant::now() + Duration::from_secs(3));
                            let _ = event_tx.send(AppEvent::Status("Initiating Wi-Fi scan...".to_string())).await;
                            
                            // Send intermediate state
                            let active_ssid = nm_client.get_active_ssid(dev_path).await.ok().flatten();
                            let aps = nm_client.list_wifi_aps(dev_path).await.unwrap_or_default();
                            let _ = event_tx.send(AppEvent::WifiState {
                                scanning: true,
                                interface: wifi_interface.clone(),
                                active_ssid: active_ssid.clone(),
                                access_points: aps,
                            }).await;
                            
                            // Spawn asynchronous scan that sleeps for 2 seconds then reports results
                            let nm_c = nm_client.clone();
                            let dev_p = dev_path.clone();
                            let ev_tx = event_tx.clone();
                            let iface = wifi_interface.clone();
                            
                            tokio::spawn(async move {
                                if let Err(e) = nm_c.trigger_wifi_scan(&dev_p).await {
                                    let _ = ev_tx.send(AppEvent::Error(format!("Wi-Fi Scan failed: {}", e))).await;
                                }
                                // Sleep to let NM gather AP results
                                tokio::time::sleep(Duration::from_secs(3)).await;
                                
                                let active_ssid = nm_c.get_active_ssid(&dev_p).await.ok().flatten();
                                let aps = nm_c.list_wifi_aps(&dev_p).await.unwrap_or_default();
                                let _ = ev_tx.send(AppEvent::WifiState {
                                    scanning: false,
                                    interface: iface,
                                    active_ssid,
                                    access_points: aps,
                                }).await;
                                let _ = ev_tx.send(AppEvent::Status("Wi-Fi scan finished.".to_string())).await;
                            });
                        } else {
                            let _ = event_tx.send(AppEvent::Error("Wi-Fi hardware/service not available".to_string())).await;
                        }
                    }
                    
                    AppCmd::WifiConnect { ap_path, ssid, password } => {
                        if let (Some(ref nm_client), Some(ref dev_path)) = (&nm, &wifi_dev_path) {
                            let _ = event_tx.send(AppEvent::Status(format!("Connecting to Wi-Fi: {}...", ssid))).await;
                            let nm_c = nm_client.clone();
                            let dev_p = dev_path.clone();
                            let ev_tx = event_tx.clone();
                            let iface = wifi_interface.clone();
                            
                            tokio::spawn(async move {
                                let pw = password.as_deref();
                                match nm_c.connect_wifi(&dev_p, &ap_path, &ssid, pw).await {
                                    Ok(_) => {
                                        let _ = ev_tx.send(AppEvent::Status(format!("Successfully connected to {}", ssid))).await;
                                        // Update state
                                        let active_ssid = nm_c.get_active_ssid(&dev_p).await.ok().flatten();
                                        let aps = nm_c.list_wifi_aps(&dev_p).await.unwrap_or_default();
                                        let _ = ev_tx.send(AppEvent::WifiState {
                                            scanning: false,
                                            interface: iface,
                                            active_ssid,
                                            access_points: aps,
                                        }).await;
                                    }
                                    Err(e) => {
                                        let _ = ev_tx.send(AppEvent::Error(format!("Connection to {} failed: {}", ssid, e))).await;
                                    }
                                }
                            });
                        }
                    }
                    
                    AppCmd::WifiDisconnect => {
                        if let (Some(ref nm_client), Some(ref dev_path)) = (&nm, &wifi_dev_path) {
                            let _ = event_tx.send(AppEvent::Status("Disconnecting from Wi-Fi...".to_string())).await;
                            match nm_client.disconnect_wifi(dev_path).await {
                                Ok(_) => {
                                    let _ = event_tx.send(AppEvent::Status("Disconnected.".to_string())).await;
                                }
                                Err(e) => {
                                    let _ = event_tx.send(AppEvent::Error(format!("Disconnect failed: {}", e))).await;
                                }
                            }
                        }
                    }
                    
                    AppCmd::BtScanToggle => {
                        if let Some(ref bt_client) = bt {
                            if bt_discovery_stream.is_some() {
                                let _ = event_tx.send(AppEvent::Status("Stopping Bluetooth discovery...".to_string())).await;
                                bt_discovery_stream = None;
                                bt_scanning = false;
                                let _ = event_tx.send(AppEvent::Status("Bluetooth discovery stopped.".to_string())).await;
                            } else {
                                let _ = event_tx.send(AppEvent::Status("Starting Bluetooth discovery...".to_string())).await;
                                match bt_client.start_scan().await {
                                    Ok(stream) => {
                                        bt_discovery_stream = Some(stream);
                                        bt_scanning = true;
                                        let _ = event_tx.send(AppEvent::Status("Bluetooth discovery started.".to_string())).await;
                                    }
                                    Err(e) => {
                                        let _ = event_tx.send(AppEvent::Error(format!("Failed to start discovery: {}", e))).await;
                                    }
                                }
                            }
                            
                            if let Ok(devices) = bt_client.list_devices().await {
                                let _ = event_tx.send(AppEvent::BtState {
                                    scanning: bt_scanning,
                                    devices,
                                }).await;
                            }
                        } else {
                            let _ = event_tx.send(AppEvent::Error("Bluetooth hardware/service not available".to_string())).await;
                        }
                    }
                    
                    AppCmd::BtConnect { address, name } => {
                        if let Some(ref bt_client) = bt {
                            let _ = event_tx.send(AppEvent::Status(format!("Connecting to Bluetooth device \"{}\" ({})...", name, address))).await;
                            let bt_c = bt_client.clone();
                            let ev_tx = event_tx.clone();
                            tokio::spawn(async move {
                                match bt_c.connect_device(address).await {
                                    Ok(_) => {
                                        let _ = ev_tx.send(AppEvent::Status(format!("Connected to \"{}\"", name))).await;
                                    }
                                    Err(e) => {
                                        let _ = ev_tx.send(AppEvent::Error(format!("Connection to \"{}\" ({}) failed: {}", name, address, e))).await;
                                    }
                                }
                            });
                        }
                    }
                    
                    AppCmd::BtDisconnect { address, name } => {
                        if let Some(ref bt_client) = bt {
                            let _ = event_tx.send(AppEvent::Status(format!("Disconnecting from Bluetooth device \"{}\" ({})...", name, address))).await;
                            let bt_c = bt_client.clone();
                            let ev_tx = event_tx.clone();
                            tokio::spawn(async move {
                                match bt_c.disconnect_device(address).await {
                                    Ok(_) => {
                                        let _ = ev_tx.send(AppEvent::Status(format!("Disconnected from \"{}\"", name))).await;
                                    }
                                    Err(e) => {
                                        let _ = ev_tx.send(AppEvent::Error(format!("Disconnect from \"{}\" ({}) failed: {}", name, address, e))).await;
                                    }
                                }
                            });
                        }
                    }
                    
                    AppCmd::BtPair { address, name } => {
                        if let Some(ref bt_client) = bt {
                            let _ = event_tx.send(AppEvent::Status(format!("Pairing with Bluetooth device \"{}\" ({})...", name, address))).await;
                            let bt_c = bt_client.clone();
                            let ev_tx = event_tx.clone();
                            tokio::spawn(async move {
                                match bt_c.pair_device(address).await {
                                    Ok(_) => {
                                        let _ = ev_tx.send(AppEvent::Status(format!("Successfully paired with \"{}\"", name))).await;
                                    }
                                    Err(e) => {
                                        let _ = ev_tx.send(AppEvent::Error(format!("Pairing with \"{}\" ({}) failed: {}", name, address, e))).await;
                                    }
                                }
                            });
                        }
                    }
                    
                    AppCmd::BtTrust { address, name, trust } => {
                        if let Some(ref bt_client) = bt {
                            let status = if trust { "Trusting" } else { "Untrusting" };
                            let _ = event_tx.send(AppEvent::Status(format!("{} device \"{}\" ({})...", status, name, address))).await;
                            match bt_client.set_trusted(address, trust).await {
                                Ok(_) => {
                                    let state = if trust { "trusted" } else { "untrusted" };
                                    let _ = event_tx.send(AppEvent::Status(format!("Device \"{}\" is now {}", name, state))).await;
                                }
                                Err(e) => {
                                    let _ = event_tx.send(AppEvent::Error(format!("Failed to set trust for \"{}\": {}", name, e))).await;
                                }
                            }
                        }
                    }
                    
                    AppCmd::BtBlock { address, name, block } => {
                        if let Some(ref bt_client) = bt {
                            let status = if block { "Blocking" } else { "Unblocking" };
                            let _ = event_tx.send(AppEvent::Status(format!("{} device \"{}\" ({})...", status, name, address))).await;
                            match bt_client.set_blocked(address, block).await {
                                Ok(_) => {
                                    let state = if block { "blocked" } else { "unblocked" };
                                    let _ = event_tx.send(AppEvent::Status(format!("Device \"{}\" is now {}", name, state))).await;
                                }
                                Err(e) => {
                                    let _ = event_tx.send(AppEvent::Error(format!("Failed to set block for \"{}\": {}", name, e))).await;
                                }
                            }
                        }
                    }
                    
                    AppCmd::BtRemove { address, name } => {
                        if let Some(ref bt_client) = bt {
                            let _ = event_tx.send(AppEvent::Status(format!("Removing Bluetooth device \"{}\" ({})...", name, address))).await;
                            match bt_client.remove_device(address).await {
                                Ok(_) => {
                                    let _ = event_tx.send(AppEvent::Status(format!("Device \"{}\" removed/forgotten.", name))).await;
                                }
                                Err(e) => {
                                    let _ = event_tx.send(AppEvent::Error(format!("Failed to remove device \"{}\": {}", name, e))).await;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// UI Keyboard Event Handler
async fn handle_key(
    key: KeyEvent,
    app: &mut App,
    cmd_tx: &mpsc::Sender<AppCmd>,
) -> Result<(), Box<dyn Error>> {
    // Check for Ctrl+C to terminate TUI immediately
    if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
        app.running = false;
        return Ok(());
    }

    // If in password input mode, handle text entry
    if let Some(ref mut prompt) = app.password_prompt {
        match key.code {
            KeyCode::Enter => {
                let password = if prompt.input.is_empty() {
                    None
                } else {
                    Some(prompt.input.clone())
                };
                let _ = cmd_tx.send(AppCmd::WifiConnect {
                    ap_path: prompt.ap_path.clone(),
                    ssid: prompt.ssid.clone(),
                    password,
                }).await;
                app.password_prompt = None;
            }
            KeyCode::Esc => {
                app.password_prompt = None;
                app.show_status("Connection canceled.".to_string(), false);
            }
            KeyCode::Backspace => {
                prompt.input.pop();
            }
            KeyCode::Char(c) => {
                prompt.input.push(c);
            }
            _ => {}
        }
        return Ok(());
    }

    // Normal mode key handling
    match key.code {
        KeyCode::Char('q') => {
            app.running = false;
        }
        
        KeyCode::Tab => {
            app.active_tab = match app.active_tab {
                Tab::Wifi => Tab::Bluetooth,
                Tab::Bluetooth => Tab::Wifi,
            };
        }

        KeyCode::Char('1') => {
            app.active_tab = Tab::Wifi;
        }

        KeyCode::Char('2') => {
            app.active_tab = Tab::Bluetooth;
        }
        
        KeyCode::Down | KeyCode::Char('j') => {
            match app.active_tab {
                Tab::Wifi => app.select_next_wifi(),
                Tab::Bluetooth => app.select_next_bt(),
            }
        }
        
        KeyCode::Up | KeyCode::Char('k') => {
            match app.active_tab {
                Tab::Wifi => app.select_prev_wifi(),
                Tab::Bluetooth => app.select_prev_bt(),
            }
        }
        
        KeyCode::Char('s') => {
            match app.active_tab {
                Tab::Wifi => {
                    let _ = cmd_tx.send(AppCmd::WifiScan).await;
                }
                Tab::Bluetooth => {
                    let _ = cmd_tx.send(AppCmd::BtScanToggle).await;
                }
            }
        }
        
        KeyCode::Enter => {
            match app.active_tab {
                Tab::Wifi => {
                    if let Some(idx) = app.wifi_table_state.selected() {
                        if let Some(ap) = app.wifi_aps.get(idx) {
                            if ap.is_secure
                                && !ap.is_saved
                                && app.wifi_active_ssid.as_ref() != Some(&ap.ssid)
                            {
                                // Prompt password
                                app.password_prompt = Some(PasswordPrompt {
                                    ssid: ap.ssid.clone(),
                                    ap_path: ap.path.clone(),
                                    input: String::new(),
                                });
                            } else {
                                // Connect immediately (open Wi-Fi or already saved)
                                let _ = cmd_tx.send(AppCmd::WifiConnect {
                                    ap_path: ap.path.clone(),
                                    ssid: ap.ssid.clone(),
                                    password: None,
                                }).await;
                            }
                        }
                    }
                }
                Tab::Bluetooth => {
                    if let Some(idx) = app.bt_table_state.selected() {
                        if let Some(dev) = app.bt_devices.get(idx) {
                            if dev.is_connected {
                                let _ = cmd_tx.send(AppCmd::BtDisconnect { address: dev.address, name: dev.name.clone() }).await;
                            } else {
                                let _ = cmd_tx.send(AppCmd::BtConnect { address: dev.address, name: dev.name.clone() }).await;
                            }
                        }
                    }
                }
            }
        }

        KeyCode::Char('c') => {
            if app.active_tab == Tab::Bluetooth {
                if let Some(idx) = app.bt_table_state.selected() {
                    if let Some(dev) = app.bt_devices.get(idx) {
                        if dev.is_connected {
                            let _ = cmd_tx.send(AppCmd::BtDisconnect { address: dev.address, name: dev.name.clone() }).await;
                        } else {
                            let _ = cmd_tx.send(AppCmd::BtConnect { address: dev.address, name: dev.name.clone() }).await;
                        }
                    }
                }
            }
        }
        
        KeyCode::Char('d') => {
            match app.active_tab {
                Tab::Wifi => {
                    let _ = cmd_tx.send(AppCmd::WifiDisconnect).await;
                }
                Tab::Bluetooth => {
                    if let Some(idx) = app.bt_table_state.selected() {
                        if let Some(dev) = app.bt_devices.get(idx) {
                            if dev.is_connected {
                                let _ = cmd_tx.send(AppCmd::BtDisconnect { address: dev.address, name: dev.name.clone() }).await;
                            }
                        }
                    }
                }
            }
        }
        
        KeyCode::Char('p') => {
            if app.active_tab == Tab::Bluetooth {
                if let Some(idx) = app.bt_table_state.selected() {
                    if let Some(dev) = app.bt_devices.get(idx) {
                        let _ = cmd_tx.send(AppCmd::BtPair { address: dev.address, name: dev.name.clone() }).await;
                    }
                }
            }
        }
        
        KeyCode::Char('t') => {
            if app.active_tab == Tab::Bluetooth {
                if let Some(idx) = app.bt_table_state.selected() {
                    if let Some(dev) = app.bt_devices.get(idx) {
                        let _ = cmd_tx.send(AppCmd::BtTrust { address: dev.address, name: dev.name.clone(), trust: !dev.is_trusted }).await;
                    }
                }
            }
        }
        
        KeyCode::Char('b') => {
            if app.active_tab == Tab::Bluetooth {
                if let Some(idx) = app.bt_table_state.selected() {
                    if let Some(dev) = app.bt_devices.get(idx) {
                        let _ = cmd_tx.send(AppCmd::BtBlock { address: dev.address, name: dev.name.clone(), block: !dev.is_blocked }).await;
                    }
                }
            }
        }
        
        KeyCode::Delete => {
            if app.active_tab == Tab::Bluetooth {
                if let Some(idx) = app.bt_table_state.selected() {
                    if let Some(dev) = app.bt_devices.get(idx) {
                        let _ = cmd_tx.send(AppCmd::BtRemove { address: dev.address, name: dev.name.clone() }).await;
                    }
                }
            }
        }
        
        _ => {}
    }

    Ok(())
}

// UI Drawing / Layout Function
fn ui_draw(f: &mut Frame, app: &mut App) {
    let size = f.size();
    
    // Main outer vertical layout: Header, Tabs, Content, Messages, Footer
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(
            [
                Constraint::Length(3), // Header
                Constraint::Length(3), // Tabs
                Constraint::Min(5),    // Content area
                Constraint::Length(2), // Messages
                Constraint::Length(1), // Help Footer
            ]
            .as_ref(),
        )
        .split(size);

    // 1. Header Rendering
    let title = Paragraph::new(vec![
        Line::from(vec![
            Span::styled(" 📻 radioctl TUI ", Style::default().fg(Color::Cyan).add_modifier(Modifier::BOLD)),
            Span::styled(" v0.1.0 ", Style::default().fg(Color::DarkGray)),
            Span::styled(" - Bluetooth & Wi-Fi replacement for bluetoothctl and nmtui", Style::default().fg(Color::Gray)),
        ])
    ])
    .block(Block::default().borders(Borders::BOTTOM).border_style(Style::default().fg(Color::DarkGray)));
    f.render_widget(title, chunks[0]);

    // 2. Tabs Rendering
    let tab_titles = vec!["📡 1. Wi-Fi (nmtui-connect)", "🔵 2. Bluetooth (bluetoothctl)"];
    let select_idx = match app.active_tab {
        Tab::Wifi => 0,
        Tab::Bluetooth => 1,
    };
    let tabs = Tabs::new(tab_titles)
        .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::DarkGray)))
        .select(select_idx)
        .style(Style::default().fg(Color::Gray))
        .highlight_style(Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD));
    f.render_widget(tabs, chunks[1]);

    // 3. Content Rendering (based on Active Tab)
    match app.active_tab {
        Tab::Wifi => {
            // Wi-Fi Access Points list
            let header_cells = ["Status", "SSID", "Signal", "Security"];
            let headers = Row::new(header_cells.iter().map(|h| {
                Cell::new(*h).style(Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD))
            }))
            .height(1)
            .bottom_margin(1);

            let active_ssid = app.wifi_active_ssid.as_deref().unwrap_or("");
            let rows = app.wifi_aps.iter().map(|ap| {
                let is_current = ap.is_active || ap.ssid == active_ssid;
                let status_span = if is_current {
                    Span::styled("  connected ", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD))
                } else {
                    Span::styled("   ", Style::default().fg(Color::Gray))
                };
                
                // Signal strength bar representation
                let strength_bar = match ap.signal {
                    s if s > 75 => "▂▄▆█",
                    s if s > 50 => "▂▄▆ ",
                    s if s > 25 => "▂▄  ",
                    _ => "▂   ",
                };
                let signal_span = Span::styled(
                    format!("{}% ({})", ap.signal, strength_bar),
                    if ap.signal > 60 {
                        Style::default().fg(Color::Green)
                    } else if ap.signal > 30 {
                        Style::default().fg(Color::Yellow)
                    } else {
                        Style::default().fg(Color::Red)
                    }
                );

                let security_span = if ap.is_secure {
                    Span::styled("🔒 WPA2/WPA3", Style::default().fg(Color::Magenta))
                } else {
                    Span::styled("🔓 Open", Style::default().fg(Color::Gray))
                };

                Row::new(vec![
                    Cell::new(status_span),
                    Cell::new(Span::styled(&ap.ssid, Style::default().add_modifier(Modifier::BOLD))),
                    Cell::new(signal_span),
                    Cell::new(security_span),
                ])
            });

            // Spinner / Scanning state display
            let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
            let scan_status_text = if app.wifi_scanning {
                let frame_idx = (app.tick_count as usize / 2) % spinner.len();
                format!(" {} Scanning Wi-Fi networks...", spinner[frame_idx])
            } else {
                " 🖳 Scan idle (Press [s] to scan)".to_string()
            };

            let title_line = Line::from(vec![
                Span::styled(format!(" Wi-Fi Networks on {} ", app.wifi_interface), Style::default().add_modifier(Modifier::BOLD)),
                Span::styled(format!(" ({}) ", scan_status_text), Style::default().fg(Color::Cyan)),
            ]);

            let table = Table::new(rows, [
                Constraint::Length(14),
                Constraint::Min(25),
                Constraint::Length(16),
                Constraint::Length(14),
            ])
            .header(headers)
            .block(
                Block::default()
                    .title(title_line)
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::DarkGray))
            )
            .highlight_style(
                Style::default()
                    .bg(Color::Rgb(30, 40, 50))
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD)
            )
            .highlight_symbol("▶ ");

            f.render_stateful_widget(table, chunks[2], &mut app.wifi_table_state);
        }
        Tab::Bluetooth => {
            // Bluetooth Devices list
            let header_cells = ["Connection", "Device Name", "MAC Address", "RSSI", "Pair/Trust/Block"];
            let headers = Row::new(header_cells.iter().map(|h| {
                Cell::new(*h).style(Style::default().fg(Color::LightBlue).add_modifier(Modifier::BOLD))
            }))
            .height(1)
            .bottom_margin(1);

            let rows = app.bt_devices.iter().map(|dev| {
                let conn_span = if dev.is_connected {
                    Span::styled(" connected", Style::default().fg(Color::Green).add_modifier(Modifier::BOLD))
                } else {
                    Span::styled("  disconnected", Style::default().fg(Color::DarkGray))
                };

                let rssi_str = match dev.rssi {
                    Some(r) => format!("{} dBm", r),
                    None => "unknown".to_string(),
                };
                let rssi_span = Span::styled(rssi_str, match dev.rssi {
                    Some(r) if r > -60 => Style::default().fg(Color::Green),
                    Some(r) if r > -80 => Style::default().fg(Color::Yellow),
                    _ => Style::default().fg(Color::DarkGray),
                });

                // Tags for Paired, Trusted, Blocked
                let mut tags = Vec::new();
                if dev.is_paired {
                    tags.push(Span::styled(" PAIRED ", Style::default().bg(Color::Blue).fg(Color::White)));
                    tags.push(Span::styled(" ", Style::default()));
                }
                if dev.is_trusted {
                    tags.push(Span::styled(" TRUSTED ", Style::default().bg(Color::Cyan).fg(Color::Black)));
                    tags.push(Span::styled(" ", Style::default()));
                }
                if dev.is_blocked {
                    tags.push(Span::styled(" BLOCKED ", Style::default().bg(Color::Red).fg(Color::White)));
                }

                Row::new(vec![
                    Cell::new(conn_span),
                    Cell::new(Span::styled(&dev.name, Style::default().add_modifier(Modifier::BOLD))),
                    Cell::new(Span::styled(dev.address.to_string(), Style::default().fg(Color::Gray))),
                    Cell::new(rssi_span),
                    Cell::new(Line::from(tags)),
                ])
            });

            let spinner = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
            let scan_status_text = if app.bt_scanning {
                let frame_idx = (app.tick_count as usize / 2) % spinner.len();
                format!(" {} Scanning nearby Bluetooth devices...", spinner[frame_idx])
            } else {
                " 🖳 Scan stopped (Press [s] to toggle scanning)".to_string()
            };

            let title_line = Line::from(vec![
                Span::styled(" Bluetooth Devices ", Style::default().add_modifier(Modifier::BOLD)),
                Span::styled(format!(" ({}) ", scan_status_text), Style::default().fg(Color::Cyan)),
            ]);

            let table = Table::new(rows, [
                Constraint::Length(16),
                Constraint::Min(25),
                Constraint::Length(20),
                Constraint::Length(12),
                Constraint::Length(30),
            ])
            .header(headers)
            .block(
                Block::default()
                    .title(title_line)
                    .borders(Borders::ALL)
                    .border_style(Style::default().fg(Color::DarkGray))
            )
            .highlight_style(
                Style::default()
                    .bg(Color::Rgb(30, 40, 50))
                    .fg(Color::White)
                    .add_modifier(Modifier::BOLD)
            )
            .highlight_symbol("▶ ");

            f.render_stateful_widget(table, chunks[2], &mut app.bt_table_state);
        }
    }

    // 4. Message / Status Bar Rendering
    if let Some((ref msg, is_error)) = app.status_message {
        let style = if is_error {
            Style::default().fg(Color::Red).add_modifier(Modifier::BOLD)
        } else {
            Style::default().fg(Color::Green).add_modifier(Modifier::BOLD)
        };
        let prefix = if is_error { "🚨 ERROR: " } else { "ℹ STATUS: " };
        let msg_p = Paragraph::new(vec![
            Line::from(vec![
                Span::styled(prefix, style),
                Span::styled(msg, Style::default().fg(Color::White)),
            ])
        ])
        .block(Block::default().borders(Borders::TOP).border_style(Style::default().fg(Color::DarkGray)));
        f.render_widget(msg_p, chunks[3]);
    } else {
        let empty_p = Paragraph::new("")
            .block(Block::default().borders(Borders::TOP).border_style(Style::default().fg(Color::DarkGray)));
        f.render_widget(empty_p, chunks[3]);
    }

    // 5. Help Footer Rendering
    let help_text = match app.active_tab {
        Tab::Wifi => " [Tab] Switch Tab | [s] Scan Wifi | [Enter] Connect AP | [d] Disconnect | [q] Quit",
        Tab::Bluetooth => " [Tab] Switch Tab | [s] Toggle Scan | [Enter/c] Connect | [d] Discon. | [p] Pair | [t] Trust | [b] Block | [Del] Remove | [q] Quit",
    };
    let footer = Paragraph::new(Span::styled(help_text, Style::default().fg(Color::DarkGray)));
    f.render_widget(footer, chunks[4]);

    // Draw Password Prompt Modal Popup if active
    if let Some(ref prompt) = app.password_prompt {
        let area = centered_rect(60, 25, size);
        f.render_widget(Clear, area); // Clear the area below the modal
        
        let modal_layout = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(2), // Prompt label
                Constraint::Length(3), // Input field
                Constraint::Length(1), // Help footer
            ].as_ref())
            .margin(2)
            .split(area);

        // Outer block
        let outer_block = Block::default()
            .title(Span::styled(" Wi-Fi Password Required ", Style::default().fg(Color::Yellow).add_modifier(Modifier::BOLD)))
            .borders(Borders::ALL)
            .border_style(Style::default().fg(Color::Yellow));
        f.render_widget(outer_block, area);

        let label = Paragraph::new(format!("Connecting to secure network: {}", prompt.ssid));
        f.render_widget(label, modal_layout[0]);

        // Draw masked password
        let masked_input = "*".repeat(prompt.input.len());
        let input_para = Paragraph::new(masked_input)
            .block(Block::default().borders(Borders::ALL).border_style(Style::default().fg(Color::Cyan)).title("Password"));
        f.render_widget(input_para, modal_layout[1]);

        let help = Paragraph::new(Span::styled("[Enter] Connect | [Esc] Cancel", Style::default().fg(Color::DarkGray)));
        f.render_widget(help, modal_layout[2]);
    }
}

// Helper to center a rect
fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints(
            [
                Constraint::Percentage((100 - percent_y) / 2),
                Constraint::Percentage(percent_y),
                Constraint::Percentage((100 - percent_y) / 2),
            ]
            .as_ref(),
        )
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints(
            [
                Constraint::Percentage((100 - percent_x) / 2),
                Constraint::Percentage(percent_x),
                Constraint::Percentage((100 - percent_x) / 2),
            ]
            .as_ref(),
        )
        .split(popup_layout[1])[1]
}

// Sub-widgets mapping for cell types, since Cell can be imported from std or ratatui
use ratatui::widgets::Cell;
