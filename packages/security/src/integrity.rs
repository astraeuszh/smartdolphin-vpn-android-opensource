use std::collections::HashMap;
use std::fs;
use std::path::{Path, PathBuf};

use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use sha2::{Digest, Sha256};

use crate::error::{CoreError, CoreResult};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ManifestEntry {
    pub version: String,
    pub build: String,
    pub url: String,
    pub sha256: String,
    pub size: u64,
    pub signature: String,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct UpdateManifest {
    pub min_version: String,
    pub force_update: bool,
    pub packages: Vec<ManifestEntry>,
}

pub fn verify_manifest_signature(
    manifest: &UpdateManifest,
    public_key_hex: &str,
) -> CoreResult<()> {
    let pk_bytes = hex::decode(public_key_hex.trim())
        .map_err(|e| CoreError::Update(format!("bad public key: {e}")))?;
    let pk = VerifyingKey::from_bytes(
        pk_bytes
            .as_slice()
            .try_into()
            .map_err(|_| CoreError::Update("public key length".into()))?,
    )
    .map_err(|e| CoreError::Update(e.to_string()))?;

    for pkg in &manifest.packages {
        let msg = canonical_package_bytes(pkg);
        let sig_bytes = hex::decode(pkg.signature.trim())
            .map_err(|e| CoreError::Update(format!("bad signature: {e}")))?;
        let sig = Signature::from_bytes(
            sig_bytes
                .as_slice()
                .try_into()
                .map_err(|_| CoreError::Update("signature length".into()))?,
        );
        pk.verify(&msg, &sig)
            .map_err(|_| CoreError::Update(format!("invalid signature for {}", pkg.version)))?;
    }
    Ok(())
}

fn canonical_package_bytes(pkg: &ManifestEntry) -> Vec<u8> {
    format!(
        "{}|{}|{}|{}|{}",
        pkg.version, pkg.build, pkg.url, pkg.sha256, pkg.size
    )
    .into_bytes()
}

pub fn verify_downloaded_bytes(data: &[u8], expected_sha256: &str) -> CoreResult<()> {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let got = hex::encode(hasher.finalize());
    if got.to_lowercase() != expected_sha256.trim().to_lowercase() {
        return Err(CoreError::Update(format!(
            "sha256 mismatch expected {expected_sha256} got {got}"
        )));
    }
    Ok(())
}

pub struct IntegrityRegistry {
    path: PathBuf,
    entries: HashMap<String, String>,
}

impl IntegrityRegistry {
    pub fn load(path: impl AsRef<Path>) -> CoreResult<Self> {
        let path = path.as_ref().to_path_buf();
        if !path.exists() {
            return Ok(Self {
                path,
                entries: HashMap::new(),
            });
        }
        let raw = fs::read_to_string(&path)?;
        let entries: HashMap<String, String> = serde_json::from_str(&raw)?;
        Ok(Self { path, entries })
    }

    pub fn verify_file(&self, label: &str, file: &Path) -> CoreResult<()> {
        if let Some(expected) = self.entries.get(label) {
            let got = crate::device::file_sha256(file)?;
            if got != *expected {
                return Err(CoreError::Integrity(format!(
                    "{label} tampered: expected {expected} got {got}"
                )));
            }
        }
        Ok(())
    }

    pub fn set_hash(&mut self, label: &str, file: &Path) -> CoreResult<()> {
        let hash = crate::device::file_sha256(file)?;
        self.entries.insert(label.to_string(), hash);
        Ok(())
    }

    pub fn save(&self) -> CoreResult<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let raw = serde_json::to_string_pretty(&self.entries)?;
        let tmp = self.path.with_extension("tmp");
        fs::write(&tmp, raw)?;
        fs::rename(tmp, &self.path)?;
        Ok(())
    }
}
