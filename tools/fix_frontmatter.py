# tools/fix_frontmatter.py
# Minimal, conservative fixer for Jekyll/MM front-matter:
# - ensure layout: single
# - ensure published: true (you can flip manually later)
# - coerce date to a string if it's not already
# - leaves everything else untouched

import os, io, sys, re, json
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Missing dependency: pyyaml\nRun: python -m pip install pyyaml", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
POSTS_DIRS = [ROOT / "_posts"]  # only posts; drafts usually already OK

def split_front_matter(text: str):
    """
    Return (fm_text, body_text) or (None, text) if not present.
    """
    if not text.startswith("---"):
        return None, text
    parts = text.split("\n", 1)
    rest = parts[1] if len(parts) > 1 else ""
    idx = rest.find("\n---")
    if idx == -1:
        return None, text
    fm_text = rest[:idx]
    body_text = rest[idx+4:]
    return fm_text, body_text.lstrip("\n")

def dump_yaml_preserve(yobj) -> str:
    # compact, block style, preserve order
    return yaml.safe_dump(
        yobj,
        sort_keys=False,
        allow_unicode=True,
        width=1000,
        default_flow_style=False
    ).strip()

def coerce_date_to_str(val):
    # If already a str, keep as is.
    if isinstance(val, str):
        return val
    # If numeric (timestamp), stringify it (Jekyll will read it as string literal).
    if isinstance(val, (int, float)):
        return str(val)
    # If something else (e.g., parsed datetime), stringify.
    return str(val)

def fix_file(path: Path):
    txt = path.read_text(encoding="utf-8")
    fm, body = split_front_matter(txt)
    if fm is None:
        print(f"  – SKIP (no front matter): {path}")
        return False

    try:
        data = yaml.safe_load(fm) or {}
        if not isinstance(data, dict):
            print(f"  – WARN (front matter not a mapping): {path}")
            return False
    except Exception as e:
        print(f"  – WARN (YAML parse error): {path} -> {e}")
        return False

    changed = False

    # layout
    if "layout" not in data or not data["layout"]:
        data["layout"] = "single"
        changed = True

    # published
    if "published" not in data:
        data["published"] = True
        changed = True

    # date: coerce to string if not already
    if "date" in data and not isinstance(data["date"], (str, int, float)):
        data["date"] = coerce_date_to_str(data["date"])
        changed = True

    # Write back only if changed
    if changed:
        new_fm = dump_yaml_preserve(data)
        new_txt = "---\n" + new_fm + "\n---\n" + body
        path.write_text(new_txt, encoding="utf-8")
        print(f"  ✓ FIXED: {path.name}")
    else:
        print(f"  • OK   : {path.name}")
    return changed

def main():
    total = 0
    fixed = 0
    for d in POSTS_DIRS:
        if not d.exists():
            continue
        for p in sorted(d.glob("*.md")):
            total += 1
            if fix_file(p):
                fixed += 1
    print(f"\nSummary: {fixed}/{total} files updated.")

if __name__ == "__main__":
    main()
