use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use hkdf::Hkdf;
use rand::RngCore;
use sha2::Sha256;

use crate::error::{CoreError, CoreResult};

const NONCE_LEN: usize = 12;

pub fn derive_storage_key(machine_key: &[u8], salt: &str) -> [u8; 32] {
    let hk = Hkdf::<Sha256>::new(Some(salt.as_bytes()), machine_key);
    let mut okm = [0u8; 32];
    hk.expand(b"smartdolphin-auth-v1", &mut okm)
        .expect("hkdf expand");
    okm
}

pub fn encrypt_blob(key: &[u8; 32], plaintext: &[u8]) -> CoreResult<String> {
    let cipher = Aes256Gcm::new_from_slice(key)
        .map_err(|e| CoreError::Crypto(e.to_string()))?;
    let mut nonce = [0u8; NONCE_LEN];
    rand::rng().fill_bytes(&mut nonce);
    let ct = cipher
        .encrypt(Nonce::from_slice(&nonce), plaintext)
        .map_err(|e| CoreError::Crypto(e.to_string()))?;
    Ok(base64::Engine::encode(
        &base64::engine::general_purpose::STANDARD,
        [&nonce[..], &ct[..]].concat(),
    ))
}

pub fn decrypt_blob(key: &[u8; 32], encoded: &str) -> CoreResult<Vec<u8>> {
    let raw = base64::Engine::decode(&base64::engine::general_purpose::STANDARD, encoded)
        .map_err(|e| CoreError::Crypto(e.to_string()))?;
    if raw.len() <= NONCE_LEN {
        return Err(CoreError::Crypto("ciphertext too short".into()));
    }
    let (nonce, ct) = raw.split_at(NONCE_LEN);
    let cipher = Aes256Gcm::new_from_slice(key)
        .map_err(|e| CoreError::Crypto(e.to_string()))?;
    cipher
        .decrypt(Nonce::from_slice(nonce), ct)
        .map_err(|e| CoreError::Crypto(e.to_string()))
}

pub fn hash_password(password: &str) -> CoreResult<String> {
    bcrypt::hash(password, bcrypt::DEFAULT_COST).map_err(|e| CoreError::Crypto(e.to_string()))
}

pub fn verify_password(hash: &str, password: &str) -> bool {
    bcrypt::verify(password, hash).unwrap_or(false)
}

pub fn random_token(len: usize) -> String {
    use rand::RngCore;
    let mut buf = vec![0u8; len];
    rand::rng().fill_bytes(&mut buf);
    hex::encode(buf)
}
