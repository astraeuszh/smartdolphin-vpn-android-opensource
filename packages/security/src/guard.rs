use std::env;
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::Path;

use crate::error::{CoreError, CoreResult};

/// 反调试：检测 TracerPid。
pub fn detect_debugger() -> CoreResult<()> {
    let status = fs::File::open("/proc/self/status")?;
    let reader = BufReader::new(status);
    for line in reader.lines() {
        let line = line?;
        if let Some(pid) = line.strip_prefix("TracerPid:") {
            let pid = pid.trim();
            if pid != "0" {
                return Err(CoreError::Security(format!(
                    "debugger attached tracer_pid={pid}"
                )));
            }
            return Ok(());
        }
    }
    Ok(())
}

/// 外部恶意注入：检测 LD_PRELOAD / DYLD_INSERT_LIBRARIES。
pub fn detect_injection() -> CoreResult<()> {
    for key in ["LD_PRELOAD", "DYLD_INSERT_LIBRARIES", "LD_AUDIT"] {
        if let Ok(v) = env::var(key) {
            if !v.trim().is_empty() {
                return Err(CoreError::Security(format!("{key}={v}")));
            }
        }
    }
    Ok(())
}

/// 高权限运行校验：生产环境建议 root 运行 VPN 核心组件。
pub fn check_privilege(require_root: bool) -> CoreResult<()> {
    let uid = unsafe { libc::geteuid() };
    if require_root && uid != 0 {
        return Err(CoreError::Security(
            "root privileges required for VPN core".into(),
        ));
    }
    Ok(())
}

/// 客户端进程守护：单实例锁，防止多开篡改会话。
pub fn acquire_daemon_lock(lock_path: &Path) -> CoreResult<std::fs::File> {
    if let Some(parent) = lock_path.parent() {
        fs::create_dir_all(parent)?;
    }
    use std::fs::OpenOptions;
    use std::os::unix::fs::OpenOptionsExt;
    let file = OpenOptions::new()
        .write(true)
        .create(true)
        .mode(0o600)
        .open(lock_path)?;
    use std::os::unix::io::AsRawFd;
    let fd = file.as_raw_fd();
    let rc = unsafe { libc::flock(fd, libc::LOCK_EX | libc::LOCK_NB) };
    if rc != 0 {
        return Err(CoreError::Security(
            "another DolphinVPN instance is running".into(),
        ));
    }
    Ok(file)
}

/// 启动自检：反调试 + 注入检测 + 可选完整性校验。
pub fn startup_self_check(
    binary: &Path,
    registry: Option<&crate::integrity::IntegrityRegistry>,
) -> CoreResult<()> {
    detect_debugger()?;
    detect_injection()?;
    if let Some(reg) = registry {
        reg.verify_file("cli", binary)?;
    }
    Ok(())
}
