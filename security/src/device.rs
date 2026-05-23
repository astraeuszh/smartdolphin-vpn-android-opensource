use sha2::{Digest, Sha256};
use std::fs;
use std::path::Path;

use crate::error::{CoreError, CoreResult};

/// 本机唯一设备标识：machine-id + hostname 哈希。
pub fn collect_device_id() -> CoreResult<String> {
    let machine_id = read_machine_id()?;
    let hostname = read_hostname();
    let mut hasher = Sha256::new();
    hasher.update(b"smartdolphin-device-v1");
    hasher.update(machine_id.as_bytes());
    hasher.update(hostname.as_bytes());
    Ok(hex::encode(hasher.finalize()))
}

fn read_machine_id() -> CoreResult<String> {
    for path in ["/etc/machine-id", "/var/lib/dbus/machine-id"] {
        if let Ok(raw) = fs::read_to_string(path) {
            let id = raw.trim();
            if !id.is_empty() {
                return Ok(id.to_string());
            }
        }
    }
    Err(CoreError::Security("machine-id unavailable".into()))
}

fn read_hostname() -> String {
    fs::read_to_string("/etc/hostname")
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "unknown".into())
}

pub fn machine_storage_seed() -> CoreResult<Vec<u8>> {
    let id = read_machine_id()?;
    Ok(id.into_bytes())
}

pub fn file_sha256(path: &Path) -> CoreResult<String> {
    let data = fs::read(path)?;
    let mut hasher = Sha256::new();
    hasher.update(&data);
    Ok(hex::encode(hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_id_stable_length() {
        if read_machine_id().is_ok() {
            let id = collect_device_id().unwrap();
            assert_eq!(id.len(), 64);
        }
    }
}
