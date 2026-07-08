"""Translate lib/l10n/app_strings_en.dart → assets/l10n/{es,pt_BR,de,fr,ja,ko}.json (batch MT)."""
from __future__ import annotations

import json
import re
import sys
import time
from pathlib import Path

from deep_translator import GoogleTranslator

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tool"))
from l10n_parse import parse_app_strings_dart  # noqa: E402

EN_DART = ROOT / "lib" / "l10n" / "app_strings_en.dart"

TARGETS: list[tuple[str, str]] = [
    ("es", "es"),
    ("pt_BR", "pt"),
    ("de", "de"),
    ("fr", "fr"),
    ("ja", "ja"),
    ("ko", "ko"),
]

_PLACEHOLDER_RE = re.compile(r"\{([^{}]+)\}")


def protect_placeholders(text: str) -> tuple[str, list[str]]:
    parts: list[str] = []

    def repl(m: re.Match[str]) -> str:
        idx = len(parts)
        parts.append(m.group(0))
        return f"<<PH{idx}>>"

    s = _PLACEHOLDER_RE.sub(repl, text)
    return s, parts


def restore_placeholders(text: str, parts: list[str]) -> str:
    for i, ph in enumerate(parts):
        text = text.replace(f"<<PH{i}>>", ph)
    return text


def translate_map_batched(en: dict[str, str], target: str, chunk_size: int = 20) -> dict[str, str]:
    translator = GoogleTranslator(source="en", target=target)
    keys = list(en.keys())
    result: dict[str, str] = {}
    n = len(keys)
    for start in range(0, n, chunk_size):
        batch_keys = keys[start : start + chunk_size]
        protected: list[str] = []
        parts_list: list[list[str]] = []
        for k in batch_keys:
            p, parts = protect_placeholders(en[k])
            protected.append(p)
            parts_list.append(parts)
        try:
            translated = translator.translate_batch(protected)
        except Exception as e:
            print(f"  batch fail at {start}: {e}, falling back to one-by-one", flush=True)
            translated = []
            for i, p in enumerate(protected):
                try:
                    translated.append(translator.translate(p))
                    time.sleep(0.05)
                except Exception as e2:
                    print(f"  FAIL {batch_keys[i]}: {e2}", flush=True)
                    translated.append(en[batch_keys[i]])
        for k, t, parts in zip(batch_keys, translated, parts_list, strict=True):
            result[k] = restore_placeholders(t, parts)
        print(f"  ... {min(start + chunk_size, n)}/{n}", flush=True)
        time.sleep(0.2)
    return result


def is_complete(path: Path, en: dict[str, str]) -> bool:
    if not path.is_file():
        return False
    try:
        m = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    return len(m) == len(en) and set(m.keys()) == set(en.keys())


def main() -> None:
    en = parse_app_strings_dart(EN_DART)
    out_dir = ROOT / "assets" / "l10n"
    out_dir.mkdir(parents=True, exist_ok=True)
    for tag, gtarget in TARGETS:
        path = out_dir / f"{tag}.json"
        if is_complete(path, en):
            print(f"skip {tag} (already complete)", flush=True)
            continue
        print(f"Translating -> {tag} ({gtarget}) ...", flush=True)
        m = translate_map_batched(en, gtarget)
        path.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"  wrote {path.relative_to(ROOT)} ({len(m)} keys)", flush=True)


if __name__ == "__main__":
    main()
