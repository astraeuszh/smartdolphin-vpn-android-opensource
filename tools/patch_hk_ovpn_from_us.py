"""Replace HK embedded OpenVPN with US profile + remote 38.76.194.13:443 (same PKI as US/SG)."""
import base64
import re
from pathlib import Path

path = Path(__file__).resolve().parent.parent / "lib/features/servers/data/static_servers.dart"
s = path.read_text(encoding="utf-8")
m = re.search(r"const _usOpenVpnConfigBase64\s*=\s*'([^']+)'", s, re.DOTALL)
if not m:
    raise SystemExit("no us b64")
us_txt = base64.b64decode(m.group(1)).decode("utf-8")
hk_txt = re.sub(
    r"remote 154\.9\.26\.253 443",
    "remote 38.76.194.13 443",
    us_txt,
    count=1,
)
hk_b64 = base64.b64encode(hk_txt.encode("utf-8")).decode("ascii")
s2, n = re.subn(
    r"const _hkOpenVpnConfigBase64\s*=\s*'[^']+'",
    "const _hkOpenVpnConfigBase64 =\n    '%s'" % hk_b64,
    s,
    count=1,
    flags=re.DOTALL,
)
if n != 1:
    raise SystemExit("hk replace failed")
path.write_text(s2, encoding="utf-8")
print("OK")
