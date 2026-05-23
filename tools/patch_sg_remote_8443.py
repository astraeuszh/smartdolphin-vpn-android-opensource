"""Set SG OpenVPN to TCP 8443 (direct, bypasses broken ssl_preread on 443 path)."""
import base64
import re
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "lib/features/servers/data/static_servers.dart"
s = path.read_text(encoding="utf-8")
m = re.search(r"const _sgOpenVpnConfigBase64\s*=\s*'([^']+)'", s, re.DOTALL)
if not m:
    raise SystemExit("missing _sgOpenVpnConfigBase64")
raw = base64.b64decode(m.group(1)).decode("utf-8")
new = re.sub(
    r"remote 154\.193\.246\.179 443",
    "remote 154.193.246.179 8443",
    raw,
    count=1,
)
if new == raw:
    raise SystemExit("no remote line replaced")
b64 = base64.b64encode(new.encode("utf-8")).decode("ascii")
s, n = re.subn(
    r"(const _sgOpenVpnConfigBase64\s*=\s*)'[^']+'",
    r"\1'%s'" % b64,
    s,
    count=1,
)
if n != 1:
    raise SystemExit("b64 replace failed")
s = s.replace("endpoint: '154.193.246.179:443'", "endpoint: '154.193.246.179:8443'")
s = s.replace(
    "// 新加坡服务器 OpenVPN (Base64) - TCP 443（由 US 配置改 remote；VPS 需部署对应证书）",
    "// 新加坡服务器 OpenVPN (Base64) - TCP 8443（直连 OpenVPN，与 US 一致；避免 443 ssl_preread 误判）",
)
path.write_text(s, encoding="utf-8")
print("OK")
