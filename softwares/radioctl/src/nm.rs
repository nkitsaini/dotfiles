use std::collections::HashMap;
use zbus::{proxy, Connection};
use zvariant::{OwnedObjectPath, Value};
use uuid::Uuid;

#[proxy(
    interface = "org.freedesktop.NetworkManager",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager"
)]
pub trait NetworkManager {
    fn get_devices(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
    fn activate_connection(
        &self,
        connection: &zbus::zvariant::ObjectPath<'_>,
        device: &zbus::zvariant::ObjectPath<'_>,
        specific_object: &zbus::zvariant::ObjectPath<'_>,
    ) -> zbus::Result<OwnedObjectPath>;
    fn deactivate_connection(&self, active_connection: &zbus::zvariant::ObjectPath<'_>) -> zbus::Result<()>;
    fn add_and_activate_connection(
        &self,
        connection: &HashMap<String, HashMap<String, Value<'_>>>,
        device: &zbus::zvariant::ObjectPath<'_>,
        specific_object: &zbus::zvariant::ObjectPath<'_>,
    ) -> zbus::Result<(OwnedObjectPath, OwnedObjectPath)>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Device",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait Device {
    #[zbus(property)]
    fn interface(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn device_type(&self) -> zbus::Result<u32>;
    #[zbus(property)]
    fn state(&self) -> zbus::Result<u32>;
    #[zbus(property)]
    fn active_connection(&self) -> zbus::Result<OwnedObjectPath>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Device.Wireless",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait Wireless {
    fn request_scan(&self, options: &HashMap<String, Value<'_>>) -> zbus::Result<()>;
    fn get_access_points(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.AccessPoint",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait AccessPoint {
    #[zbus(property)]
    fn ssid(&self) -> zbus::Result<Vec<u8>>;
    #[zbus(property)]
    fn strength(&self) -> zbus::Result<u8>;
    #[zbus(property)]
    fn wpa_flags(&self) -> zbus::Result<u32>;
    #[zbus(property)]
    fn rsn_flags(&self) -> zbus::Result<u32>;
    #[zbus(property)]
    fn hw_address(&self) -> zbus::Result<String>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Settings",
    default_service = "org.freedesktop.NetworkManager",
    default_path = "/org/freedesktop/NetworkManager/Settings"
)]
pub trait Settings {
    fn list_connections(&self) -> zbus::Result<Vec<OwnedObjectPath>>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Settings.Connection",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait SettingsConnection {
    fn get_settings(&self) -> zbus::Result<HashMap<String, HashMap<String, OwnedValue>>>;
    fn delete(&self) -> zbus::Result<()>;
}

#[proxy(
    interface = "org.freedesktop.NetworkManager.Connection.Active",
    default_service = "org.freedesktop.NetworkManager"
)]
pub trait ActiveConnection {
    #[zbus(property)]
    fn id(&self) -> zbus::Result<String>;
    #[zbus(property)]
    fn connection(&self) -> zbus::Result<OwnedObjectPath>;
    #[zbus(property)]
    fn specific_object(&self) -> zbus::Result<OwnedObjectPath>;
    #[zbus(property)]
    fn state(&self) -> zbus::Result<u32>;
}

// Help with deserialized types
type OwnedValue = zvariant::OwnedValue;

#[derive(Debug, Clone)]
pub struct WifiApInfo {
    pub ssid: String,
    pub bssid: String,
    pub signal: u8,
    pub is_secure: bool,
    pub is_active: bool,
    pub path: String,
}

#[derive(Clone)]
pub struct NmClient {
    conn: Connection,
}

impl NmClient {
    pub async fn new() -> zbus::Result<Self> {
        let conn = Connection::system().await?;
        Ok(Self { conn })
    }

    pub async fn find_wifi_device(&self) -> zbus::Result<Option<String>> {
        let nm_proxy = NetworkManagerProxy::new(&self.conn).await?;
        let devices = nm_proxy.get_devices().await?;
        for dev_path in devices {
            let dev_proxy = DeviceProxy::builder(&self.conn)
                .path(&dev_path)?
                .build()
                .await?;
            let dev_type = dev_proxy.device_type().await?;
            if dev_type == 2 {
                // Wi-Fi device
                return Ok(Some(dev_path.to_string()));
            }
        }
        Ok(None)
    }

    pub async fn get_wifi_interface_name(&self, dev_path: &str) -> zbus::Result<String> {
        let dev_path_obj = zvariant::ObjectPath::try_from(dev_path)?;
        let dev_proxy = DeviceProxy::builder(&self.conn)
            .path(&dev_path_obj)?
            .build()
            .await?;
        dev_proxy.interface().await
    }

    pub async fn trigger_wifi_scan(&self, dev_path: &str) -> zbus::Result<()> {
        let dev_path_obj = zvariant::ObjectPath::try_from(dev_path)?;
        let wireless_proxy = WirelessProxy::builder(&self.conn)
            .path(&dev_path_obj)?
            .build()
            .await?;
        let options = HashMap::new();
        wireless_proxy.request_scan(&options).await?;
        Ok(())
    }

    pub async fn list_wifi_aps(&self, dev_path: &str) -> zbus::Result<Vec<WifiApInfo>> {
        let dev_path_obj = zvariant::ObjectPath::try_from(dev_path)?;
        
        let dev_proxy = DeviceProxy::builder(&self.conn)
            .path(&dev_path_obj)?
            .build()
            .await?;
        
        let active_conn_path = dev_proxy.active_connection().await;
        let mut active_ap_path = String::new();
        
        if let Ok(active_path) = active_conn_path {
            if active_path.as_str() != "/" {
                if let Ok(active_conn_builder) = ActiveConnectionProxy::builder(&self.conn).path(&active_path) {
                    if let Ok(active_conn_p) = active_conn_builder.build().await {
                        if let Ok(ap_path_obj) = active_conn_p.specific_object().await {
                            active_ap_path = ap_path_obj.to_string();
                        }
                    }
                }
            }
        }

        let wireless_proxy = WirelessProxy::builder(&self.conn)
            .path(&dev_path_obj)?
            .build()
            .await?;
        
        let ap_paths = wireless_proxy.get_access_points().await?;
        let mut aps = Vec::new();
        
        for ap_path in ap_paths {
            let ap_proxy = AccessPointProxy::builder(&self.conn)
                .path(&ap_path)?
                .build()
                .await?;
            
            let ssid_bytes = match ap_proxy.ssid().await {
                Ok(bytes) => bytes,
                Err(_) => continue,
            };
            let ssid = String::from_utf8_lossy(&ssid_bytes).into_owned();
            if ssid.is_empty() {
                continue;
            }
            
            let bssid = ap_proxy.hw_address().await.unwrap_or_default();
            let signal = ap_proxy.strength().await.unwrap_or(0);
            
            let wpa_flags = ap_proxy.wpa_flags().await.unwrap_or(0);
            let rsn_flags = ap_proxy.rsn_flags().await.unwrap_or(0);
            let is_secure = wpa_flags != 0 || rsn_flags != 0;
            let is_active = ap_path.as_str() == active_ap_path.as_str();
            
            aps.push(WifiApInfo {
                ssid,
                bssid,
                signal,
                is_secure,
                is_active,
                path: ap_path.to_string(),
            });
        }

        // Deduplicate by SSID, keeping the strongest signal but prioritizing the active connection
        let mut unique_aps: HashMap<String, WifiApInfo> = HashMap::new();
        for ap in aps {
            if let Some(existing) = unique_aps.get(&ap.ssid) {
                if ap.is_active || (!existing.is_active && ap.signal > existing.signal) {
                    unique_aps.insert(ap.ssid.clone(), ap);
                }
            } else {
                unique_aps.insert(ap.ssid.clone(), ap);
            }
        }

        let mut res: Vec<WifiApInfo> = unique_aps.into_values().collect();
        res.sort_by(|a, b| b.signal.cmp(&a.signal));
        Ok(res)
    }

    pub async fn get_saved_connection_path(&self, ssid: &str) -> zbus::Result<Option<String>> {
        let settings_proxy = SettingsProxy::new(&self.conn).await?;
        let conns = settings_proxy.list_connections().await?;
        for conn_path in conns {
            let conn_proxy = SettingsConnectionProxy::builder(&self.conn)
                .path(&conn_path)?
                .build()
                .await?;
            if let Ok(settings) = conn_proxy.get_settings().await {
                if let Some(wifi_settings) = settings.get("802-11-wireless") {
                    if let Some(ssid_val) = wifi_settings.get("ssid") {
                        if let Ok(Value::Array(arr)) = Value::try_from(ssid_val) {
                            let bytes: Vec<u8> = arr.iter().filter_map(|v| match v {
                                Value::U8(b) => Some(*b),
                                _ => None,
                            }).collect();
                            let conn_ssid = String::from_utf8_lossy(&bytes);
                            if conn_ssid == ssid {
                                return Ok(Some(conn_path.to_string()));
                            }
                        }
                    }
                }
            }
        }
        Ok(None)
    }

    pub async fn connect_wifi(&self, dev_path: &str, ap_path: &str, ssid: &str, password: Option<&str>) -> zbus::Result<()> {
        let nm_proxy = NetworkManagerProxy::new(&self.conn).await?;
        let dev_path_obj = zvariant::ObjectPath::try_from(dev_path)?;
        let ap_path_obj = zvariant::ObjectPath::try_from(ap_path)?;

        if let Some(saved_path) = self.get_saved_connection_path(ssid).await? {
            let saved_path_obj = zvariant::ObjectPath::try_from(saved_path.as_str())?;
            nm_proxy.activate_connection(&saved_path_obj, &dev_path_obj, &ap_path_obj).await?;
        } else {
            // Build setting maps
            let mut settings = HashMap::new();

            // connection setting
            let mut conn_setting = HashMap::new();
            let uuid_str = Uuid::new_v4().to_string();
            conn_setting.insert("id".to_string(), Value::new(ssid));
            conn_setting.insert("type".to_string(), Value::new("802-11-wireless"));
            conn_setting.insert("uuid".to_string(), Value::new(uuid_str));
            settings.insert("connection".to_string(), conn_setting);

            // wireless setting
            let mut wireless_setting = HashMap::new();
            wireless_setting.insert("ssid".to_string(), Value::new(ssid.as_bytes().to_vec()));
            wireless_setting.insert("mode".to_string(), Value::new("infrastructure"));
            settings.insert("802-11-wireless".to_string(), wireless_setting);

            // wireless-security setting (if password provided)
            if let Some(pwd) = password {
                let mut sec_setting = HashMap::new();
                sec_setting.insert("key-mgmt".to_string(), Value::new("wpa-psk"));
                sec_setting.insert("auth-alg".to_string(), Value::new("open"));
                sec_setting.insert("psk".to_string(), Value::new(pwd));
                settings.insert("802-11-wireless-security".to_string(), sec_setting);
            }

            // ipv4 setting
            let mut ipv4_setting = HashMap::new();
            ipv4_setting.insert("method".to_string(), Value::new("auto"));
            settings.insert("ipv4".to_string(), ipv4_setting);

            // ipv6 setting
            let mut ipv6_setting = HashMap::new();
            ipv6_setting.insert("method".to_string(), Value::new("auto"));
            settings.insert("ipv6".to_string(), ipv6_setting);

            nm_proxy.add_and_activate_connection(&settings, &dev_path_obj, &ap_path_obj).await?;
        }

        Ok(())
    }

    pub async fn disconnect_wifi(&self, dev_path: &str) -> zbus::Result<()> {
        let dev_path_obj = zvariant::ObjectPath::try_from(dev_path)?;
        let dev_proxy = DeviceProxy::builder(&self.conn)
            .path(&dev_path_obj)?
            .build()
            .await?;
        let active_conn_path = dev_proxy.active_connection().await?;
        if active_conn_path.as_str() != "/" {
            let nm_proxy = NetworkManagerProxy::new(&self.conn).await?;
            nm_proxy.deactivate_connection(&active_conn_path).await?;
        }
        Ok(())
    }

    pub async fn get_active_ssid(&self, dev_path: &str) -> zbus::Result<Option<String>> {
        let dev_path_obj = zvariant::ObjectPath::try_from(dev_path)?;
        let dev_proxy = DeviceProxy::builder(&self.conn)
            .path(&dev_path_obj)?
            .build()
            .await?;
        let active_conn_path = dev_proxy.active_connection().await?;
        if active_conn_path.as_str() == "/" {
            return Ok(None);
        }

        let active_conn_proxy = ActiveConnectionProxy::builder(&self.conn)
            .path(&active_conn_path)?
            .build()
            .await?;

        // 1. Get Settings Connection path
        let settings_conn_path = active_conn_proxy.connection().await?;
        
        // 2. Connect to Settings Connection
        let settings_conn_proxy = SettingsConnectionProxy::builder(&self.conn)
            .path(&settings_conn_path)?
            .build()
            .await?;

        // 3. Extract SSID from Settings
        if let Ok(settings) = settings_conn_proxy.get_settings().await {
            if let Some(wifi_settings) = settings.get("802-11-wireless") {
                if let Some(ssid_val) = wifi_settings.get("ssid") {
                    if let Ok(Value::Array(arr)) = Value::try_from(ssid_val) {
                        let bytes: Vec<u8> = arr.iter().filter_map(|v| match v {
                            Value::U8(b) => Some(*b),
                            _ => None,
                        }).collect();
                        return Ok(Some(String::from_utf8_lossy(&bytes).into_owned()));
                    }
                }
            }
        }
        Ok(None)
    }
}
