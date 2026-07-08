use crate::error::{CoreError, CoreResult};

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct VersionPolicy {
    #[serde(default = "default_min_version")]
    pub min_version: String,
    #[serde(default)]
    pub force_update: bool,
    #[serde(default)]
    pub deprecated: Vec<String>,
}

fn default_min_version() -> String {
    "1.0.0".into()
}

impl Default for VersionPolicy {
    fn default() -> Self {
        Self {
            min_version: default_min_version(),
            force_update: false,
            deprecated: vec![],
        }
    }
}

pub fn parse_version(v: &str) -> Vec<u32> {
    v.split('.')
        .map(|p| p.parse().unwrap_or(0))
        .collect()
}

pub fn compare(left: &str, right: &str) -> i32 {
    let a = parse_version(left);
    let b = parse_version(right);
    let n = a.len().max(b.len());
    for i in 0..n {
        let x = *a.get(i).unwrap_or(&0);
        let y = *b.get(i).unwrap_or(&0);
        if x < y {
            return -1;
        }
        if x > y {
            return 1;
        }
    }
    0
}

/// 客户端在线版本检测 + 低版本/淘汰版本拦截。
pub fn enforce_client_version(policy: &VersionPolicy, current: &str) -> CoreResult<()> {
    let cur = current.trim();
    if cur.is_empty() {
        return Err(CoreError::VersionTooOld {
            min: policy.min_version.clone(),
            current: "unknown".into(),
        });
    }
    for dep in &policy.deprecated {
        if compare(cur, dep) == 0 {
            return Err(CoreError::VersionDeprecated(dep.clone()));
        }
    }
    if compare(cur, &policy.min_version) < 0 {
        if policy.force_update {
            return Err(CoreError::ForceUpdate);
        }
        return Err(CoreError::VersionTooOld {
            min: policy.min_version.clone(),
            current: cur.into(),
        });
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compare_semver() {
        assert!(compare("1.0.1", "1.0.0") > 0);
        assert!(compare("0.9.9", "1.0.0") < 0);
    }
}
