"""Rewrite static_servers.dart OpenVPN base64 to use TCP 443 on remote lines."""
import re
import base64
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "lib/features/servers/data/static_servers.dart"
s = path.read_text(encoding="utf-8")
for name in ["_hkOpenVpnConfigBase64", "_usOpenVpnConfigBase64", "_sgOpenVpnConfigBase64"]:
    m = re.search(r"const %s\s*=\s*'([^']+)'" % name, s, re.DOTALL)
    if not m:
        raise SystemExit("missing " + name)
    raw = base64.b64decode(m.group(1)).decode("utf-8")
    new = re.sub(r"^(\s*remote\s+\S+)\s+8443\s*$", r"\1 443", raw, flags=re.MULTILINE)
    if new == raw:
        raise SystemExit("no remote 8443 replaced in " + name)
    b64 = base64.b64encode(new.encode("utf-8")).decode("ascii")
    s, n = re.subn(
        r"(const %s\s*=\s*)'[^']+'" % name,
        r"\1'%s'" % b64,
        s,
        count=1,
    )
    if n != 1:
        raise SystemExit("replace failed for " + name)

s = s.replace(":8443", ":443")
s = s.replace("TCP 8443", "TCP 443")
s = s.replace("8443 + TLS", "443 + TLS")
path.write_text(s, encoding="utf-8")
print("OK")
