use bluer::{Adapter, Address, Session};

#[derive(Debug, Clone)]
pub struct BtDeviceInfo {
    pub name: String,
    pub address: Address,
    pub is_connected: bool,
    pub is_paired: bool,
    pub is_trusted: bool,
    pub is_blocked: bool,
    pub rssi: Option<i16>,
}

#[derive(Clone)]
pub struct BtClient {
    _session: Session,
    adapter: Adapter,
}

impl BtClient {
    pub async fn new() -> bluer::Result<Self> {
        let session = Session::new().await?;
        let adapter = session.default_adapter().await?;
        
        // Ensure adapter is powered on
        if !adapter.is_powered().await? {
            adapter.set_powered(true).await?;
        }
        
        Ok(Self { _session: session, adapter })
    }

    pub async fn is_scanning(&self) -> bluer::Result<bool> {
        self.adapter.is_discovering().await
    }

    pub async fn start_scan(&self) -> bluer::Result<std::pin::Pin<Box<dyn futures_util::Stream<Item = bluer::AdapterEvent> + Send>>> {
        let stream = self.adapter.discover_devices().await?;
        Ok(Box::pin(stream))
    }

    pub async fn list_devices(&self) -> bluer::Result<Vec<BtDeviceInfo>> {
        let addrs = self.adapter.device_addresses().await?;
        let mut devices = Vec::new();
        
        for addr in addrs {
            if let Ok(dev) = self.adapter.device(addr) {
                let name = dev.name().await?.unwrap_or_else(|| "Unknown".to_string());
                let is_connected = dev.is_connected().await?;
                let is_paired = dev.is_paired().await?;
                let is_trusted = dev.is_trusted().await?;
                let is_blocked = dev.is_blocked().await?;
                let rssi = dev.rssi().await?;
                
                devices.push(BtDeviceInfo {
                    name,
                    address: addr,
                    is_connected,
                    is_paired,
                    is_trusted,
                    is_blocked,
                    rssi,
                });
            }
        }
        
        // Sort devices: connected first, then paired, then alphabetically by name, then MAC
        devices.sort_by(|a, b| {
            if a.is_connected != b.is_connected {
                b.is_connected.cmp(&a.is_connected)
            } else if a.is_paired != b.is_paired {
                b.is_paired.cmp(&a.is_paired)
            } else {
                a.name.cmp(&b.name).then_with(|| a.address.cmp(&b.address))
            }
        });
        
        Ok(devices)
    }

    pub async fn connect_device(&self, address: Address) -> bluer::Result<()> {
        let device = self.adapter.device(address)?;
        device.connect().await?;
        Ok(())
    }

    pub async fn disconnect_device(&self, address: Address) -> bluer::Result<()> {
        let device = self.adapter.device(address)?;
        device.disconnect().await?;
        Ok(())
    }

    pub async fn pair_device(&self, address: Address) -> bluer::Result<()> {
        let device = self.adapter.device(address)?;
        // Simple pair without custom agent (uses system bluetooth agent if running)
        device.pair().await?;
        Ok(())
    }

    pub async fn set_trusted(&self, address: Address, trusted: bool) -> bluer::Result<()> {
        let device = self.adapter.device(address)?;
        device.set_trusted(trusted).await?;
        Ok(())
    }

    pub async fn set_blocked(&self, address: Address, blocked: bool) -> bluer::Result<()> {
        let device = self.adapter.device(address)?;
        device.set_blocked(blocked).await?;
        Ok(())
    }

    pub async fn remove_device(&self, address: Address) -> bluer::Result<()> {
        self.adapter.remove_device(address).await?;
        Ok(())
    }
}
