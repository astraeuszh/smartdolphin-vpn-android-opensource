"""Extract 'en' map from app_localizations.dart into JSON (keys match LocaleJsonBundle)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path


def extract_en_map(dart_path: Path) -> dict[str, str]:
    text = dart_path.read_text(encoding="utf-8")
    start = text.index("'en': {")
    sub = text[start:]
    end_marker = "\n    'zh': {"
    end = sub.index(end_marker)
    block = sub[:end]
    # Same-line or next-line string values; supports \' inside values.
    pattern = r"'([^']+)':\s*(?:\n\s*)?'((?:[^'\\]|\\.)*)'"
    matches = re.findall(pattern, block)
    out: dict[str, str] = {}
    for key, raw in matches:
        # Unescape Dart-style single-quoted string escapes we care about.
        val = raw.replace("\\'", "'").replace("\\\\", "\\")
        out[key] = val
    return out


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    dart = root / "lib" / "l10n" / "app_localizations.dart"
    m = extract_en_map(dart)
    out_path = root / "assets" / "l10n" / "en.extracted.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(
        json.dumps(m, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {len(m)} keys to {out_path.relative_to(root)}")


if __name__ == "__main__":
    main()
