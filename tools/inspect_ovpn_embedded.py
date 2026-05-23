"""Decode static_servers.dart embedded ovpn and print remote + CA fingerprint."""
import base64
import hashlib
import re
from pathlib import Path

p = Path(__file__).resolve().parent.parent / "lib/features/servers/data/static_servers.dart"
t = p.read_text(encoding="utf-8")
for name in ["_hkOpenVpnConfigBase64", "_usOpenVpnConfigBase64", "_sgOpenVpnConfigBase64"]:
    m = re.search(r"const %s\s*=\s*'([^']+)'" % name, t, re.DOTALL)
    if not m:
        print(name, "MISSING")
        continue
    raw = base64.b64decode(m.group(1)).decode("utf-8")
    print("===", name, "===")
    for line in raw.splitlines()[:6]:
        print(line)
    ca = raw.split("<ca>")[1].split("</ca>")[0].strip() if "<ca>" in raw else ""
    h = hashlib.sha256(ca.encode()).hexdigest()[:16]
    print("  CA sha256 prefix:", h)
    print()
