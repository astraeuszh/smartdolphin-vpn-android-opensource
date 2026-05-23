use serde::{Deserialize, Serialize};

/// 账号权限等级判定：由服务端统一管控。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PermissionLevel {
    User = 0,
    Premium = 1,
    Vip = 2,
    Admin = 10,
}

impl PermissionLevel {
    pub fn as_u8(self) -> u8 {
        match self {
            Self::User => 0,
            Self::Premium => 1,
            Self::Vip => 2,
            Self::Admin => 10,
        }
    }

    pub fn from_u8(v: u8) -> Self {
        match v {
            1 => Self::Premium,
            2 => Self::Vip,
            10 => Self::Admin,
            _ => Self::User,
        }
    }

    pub fn allows_vpn(&self, banned: bool, expire_at: i64, now: i64) -> bool {
        if *self == Self::Admin {
            return !banned;
        }
        !banned && expire_at > 0 && now <= expire_at
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::User => "user",
            Self::Premium => "premium",
            Self::Vip => "vip",
            Self::Admin => "admin",
        }
    }
}
