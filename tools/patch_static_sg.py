import re
import base64
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "lib/features/servers/data/static_servers.dart"
s = path.read_text(encoding="utf-8")
m = re.search(r"const _usOpenVpnConfigBase64\s*=\s*'([^']+)'", s, re.DOTALL)
if not m:
    raise SystemExit("no us b64")
us_txt = base64.b64decode(m.group(1)).decode("utf-8")
sg_txt = re.sub(
    r"remote 154\.9\.26\.253 443",
    "remote 154.193.246.179 8443",
    us_txt,
    count=1,
)
sg_b64 = base64.b64encode(sg_txt.encode("utf-8")).decode("ascii")

insert = """
  Server(
    id: 'smartdolphin-sg',
    name: '新加坡 • SmartDolphin',
    countryCode: 'SG',
    countryName: 'Singapore',
    publicKey: 'openvpn',
    endpoint: '154.193.246.179:8443',
    allowedIps: '0.0.0.0/0, ::/0',
    hostName: '154.193.246.179',
    ip: '154.193.246.179',
    openVpnConfigDataBase64: _sgOpenVpnConfigBase64,
    regionName: 'Singapore',
    cityName: 'Singapore',
  ),"""

s2, n = re.subn(
    r"(cityName: 'Los Angeles',\s*\),)\s*(\];)",
    r"\1" + insert + r"\n\2",
    s,
    count=1,
)
if n != 1:
    raise SystemExit("server insert failed")

sg_const = f"""

// 新加坡服务器 OpenVPN (Base64) - TCP 8443（直连；避免 443 ssl_preread 误判）
const _sgOpenVpnConfigBase64 =
    '{sg_b64}';
"""

s3, n2 = re.subn(
    r"(const _usOpenVpnConfigBase64\s*=\s*'[^']+'\s*;)",
    r"\1" + sg_const,
    s2,
    count=1,
)
if n2 != 1:
    raise SystemExit("b64 insert failed")

path.write_text(s3, encoding="utf-8")
print("OK")
