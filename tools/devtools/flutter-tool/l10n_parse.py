"""Parse const Map in lib/l10n/app_strings_*.dart to dict."""
from __future__ import annotations

import re
from pathlib import Path


def parse_app_strings_dart(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    pattern = r"'([^']+)':\s*(?:\n\s*)?'((?:[^'\\]|\\.)*)'"
    out: dict[str, str] = {}
    for key, raw in re.findall(pattern, text):
        val = raw.replace("\\'", "'").replace("\\\\", "\\")
        out[key] = val
    return out
