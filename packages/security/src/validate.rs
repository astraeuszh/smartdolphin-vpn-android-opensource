use crate::error::{CoreError, CoreResult};

/// 注册信息格式合规校验：用户名 2-32 位字母数字_-，密码 8-64 且含字母与数字。
pub fn normalize_username(raw: &str) -> CoreResult<String> {
    let name = raw.trim();
    if name.len() < 2 || name.len() > 32 {
        return Err(CoreError::Validation(
            "username length must be 2-32".into(),
        ));
    }
    if !name
        .chars()
        .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
    {
        return Err(CoreError::Validation(
            "username may only contain letters, digits, _ and -".into(),
        ));
    }
    Ok(name.to_string())
}

pub fn validate_password(raw: &str) -> CoreResult<()> {
    let pw = raw.trim();
    if pw.len() < 8 || pw.len() > 64 {
        return Err(CoreError::Validation(
            "password length must be 8-64".into(),
        ));
    }
    let has_alpha = pw.chars().any(|c| c.is_ascii_alphabetic());
    let has_digit = pw.chars().any(|c| c.is_ascii_digit());
    if !has_alpha || !has_digit {
        return Err(CoreError::Validation(
            "password must contain letters and digits".into(),
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn username_ok() {
        assert!(normalize_username("test_user-1").is_ok());
    }

    #[test]
    fn password_requires_mixed() {
        assert!(validate_password("12345678").is_err());
        assert!(validate_password("abc12345").is_ok());
    }
}
