use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process;

use sd_core::crypto::{decrypt_blob, derive_storage_key, encrypt_blob};
use sd_core::device::{collect_device_id, machine_storage_seed};
use sd_core::guard::{acquire_daemon_lock, startup_self_check};
use sd_core::integrity::IntegrityRegistry;
use sd_core::update::{verify_downloaded_bytes, verify_manifest_signature, UpdateManifest};

fn err(msg: impl Into<String>) -> ! {
    eprintln!(r#"{{"ok":false,"error":"{}"}}"#, msg.into().replace('"', "'"));
    process::exit(1);
}

fn storage_key() -> [u8; 32] {
    let seed = machine_storage_seed().unwrap_or_else(|_| b"fallback-seed".to_vec());
    derive_storage_key(&seed, "smartdolphin-linux-v1")
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: sd-guard <device-id|selfcheck|session-save|session-load|session-clear|verify-update|verify-bytes>");
        process::exit(2);
    }
    match args[1].as_str() {
        "device-id" => {
            let id = collect_device_id().unwrap_or_else(|e| err(e.to_string()));
            println!(r#"{{"ok":true,"device_id":"{id}"}}"#);
        }
        "selfcheck" => {
            let bin = args
                .get(2)
                .map(PathBuf::from)
                .unwrap_or_else(|| env::current_exe().unwrap_or_else(|e| err(e.to_string())));
            let reg_path = args.get(3).cloned().unwrap_or_else(|| {
                env::var("SMARTDOLPHIN_INTEGRITY_FILE")
                    .unwrap_or_else(|_| ".local/share/smartdolphin/integrity.json".into())
            });
            let reg = IntegrityRegistry::load(&reg_path).ok();
            startup_self_check(&bin, reg.as_ref()).unwrap_or_else(|e| err(e.to_string()));
            let lock = env::var("SMARTDOLPHIN_LOCK_FILE")
                .unwrap_or_else(|_| "/tmp/smartdolphin-vpn.lock".into());
            let _guard = acquire_daemon_lock(Path::new(&lock)).unwrap_or_else(|e| err(e.to_string()));
            println!(r#"{{"ok":true,"message":"selfcheck passed"}}"#);
        }
        "session-save" => {
            if args.len() < 4 {
                err("session-save <out.enc> <plain.json>");
            }
            let out_path = &args[2];
            let in_path = &args[3];
            let raw = fs::read_to_string(in_path).unwrap_or_else(|e| err(e.to_string()));
            let key = storage_key();
            let enc = encrypt_blob(&key, raw.as_bytes()).unwrap_or_else(|e| err(e.to_string()));
            if let Some(parent) = Path::new(out_path).parent() {
                let _ = fs::create_dir_all(parent);
            }
            fs::write(out_path, enc).unwrap_or_else(|e| err(e.to_string()));
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                let _ = fs::set_permissions(out_path, fs::Permissions::from_mode(0o600));
            }
            println!(r#"{{"ok":true}}"#);
        }
        "session-load" => {
            let path = args.get(2).ok_or_else(|| err("session-load needs path")).unwrap();
            let enc = fs::read_to_string(path).unwrap_or_else(|e| err(e.to_string()));
            let key = storage_key();
            let plain = decrypt_blob(&key, enc.trim()).unwrap_or_else(|e| err(e.to_string()));
            print!("{}", String::from_utf8_lossy(&plain));
        }
        "session-clear" => {
            let path = args.get(2).ok_or_else(|| err("session-clear needs path")).unwrap();
            let _ = fs::remove_file(path);
            println!(r#"{{"ok":true}}"#);
        }
        "verify-update" => {
            let manifest_path = args
                .get(2)
                .ok_or_else(|| err("verify-update needs manifest.json"))
                .unwrap();
            let raw = fs::read_to_string(manifest_path).unwrap_or_else(|e| err(e.to_string()));
            let manifest: UpdateManifest =
                serde_json::from_str(&raw).unwrap_or_else(|e| err(e.to_string()));
            let pk = env::var("SD_UPDATE_PUBKEY").unwrap_or_default();
            if !pk.is_empty() {
                verify_manifest_signature(&manifest, &pk).unwrap_or_else(|e| err(e.to_string()));
            }
            println!(
                r#"{{"ok":true,"packages":{}}}"#,
                manifest.packages.len()
            );
        }
        "verify-bytes" => {
            let file = args.get(2).ok_or_else(|| err("verify-bytes needs file")).unwrap();
            let hash = args.get(3).ok_or_else(|| err("verify-bytes needs sha256")).unwrap();
            let data = fs::read(file).unwrap_or_else(|e| err(e.to_string()));
            verify_downloaded_bytes(&data, hash).unwrap_or_else(|e| err(e.to_string()));
            println!(r#"{{"ok":true}}"#);
        }
        other => err(format!("unknown command {other}")),
    }
}
