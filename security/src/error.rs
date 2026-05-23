use thiserror::Error;

pub type CoreResult<T> = Result<T, CoreError>;

#[derive(Debug, Error)]
pub enum CoreError {
    #[error("validation: {0}")]
    Validation(String),
    #[error("auth: {0}")]
    Auth(String),
    #[error("ban: {0}")]
    Ban(String),
    #[error("expired")]
    Expired,
    #[error("pending activation")]
    Pending,
    #[error("remote login detected")]
    RemoteLogin,
    #[error("permission denied: {0}")]
    Permission(String),
    #[error("version too old: min {min}, current {current}")]
    VersionTooOld { min: String, current: String },
    #[error("version deprecated: {0}")]
    VersionDeprecated(String),
    #[error("force update required")]
    ForceUpdate,
    #[error("integrity: {0}")]
    Integrity(String),
    #[error("security: {0}")]
    Security(String),
    #[error("update: {0}")]
    Update(String),
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("json: {0}")]
    Json(#[from] serde_json::Error),
    #[error("crypto: {0}")]
    Crypto(String),
    #[error("store: {0}")]
    Store(String),
}
