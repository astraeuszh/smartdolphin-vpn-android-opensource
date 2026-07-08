use crate::error::{CoreError, CoreResult};
use crate::permission::PermissionLevel;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct AuthSession {
    pub uid: i64,
    pub username: String,
    pub token: String,
    pub device_id: String,
    pub expire_at: i64,
    pub permission: PermissionLevel,
    pub issued_at: i64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct StoredSession {
    pub username: String,
    pub password: String,
    pub uid: i64,
    pub expire_at: i64,
    pub token: String,
    pub device_id: String,
    pub permission: u8,
}

pub fn issue_session(
    uid: i64,
    username: &str,
    device_id: &str,
    expire_at: i64,
    permission: PermissionLevel,
    token: String,
) -> AuthSession {
    AuthSession {
        uid,
        username: username.to_string(),
        token,
        device_id: device_id.to_string(),
        expire_at,
        permission,
        issued_at: chrono::Utc::now().timestamp(),
    }
}

pub fn validate_local_session(session: &AuthSession, device_id: &str) -> CoreResult<()> {
    if session.device_id != device_id {
        return Err(CoreError::RemoteLogin);
    }
    if session.expire_at > 0 && chrono::Utc::now().timestamp() > session.expire_at {
        return Err(CoreError::Expired);
    }
    Ok(())
}

pub fn stored_from_auth(session: &AuthSession, password: &str) -> StoredSession {
    StoredSession {
        username: session.username.clone(),
        password: password.to_string(),
        uid: session.uid,
        expire_at: session.expire_at,
        token: session.token.clone(),
        device_id: session.device_id.clone(),
        permission: session.permission.as_u8(),
    }
}

pub fn auth_from_stored(stored: &StoredSession) -> AuthSession {
    AuthSession {
        uid: stored.uid,
        username: stored.username.clone(),
        token: stored.token.clone(),
        device_id: stored.device_id.clone(),
        expire_at: stored.expire_at,
        permission: PermissionLevel::from_u8(stored.permission),
        issued_at: 0,
    }
}
