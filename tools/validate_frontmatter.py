#!/usr/bin/env python3
"""
FlowformLab front-matter validator
- Scans _posts/ and _drafts/ for Markdown files
- Validates minimal Jekyll + Minimal Mistakes fields
- Prints a per-file report and an overall summary
- Exits with code 1 if any errors are found (good for CI/n8n)

Requirements:
  pip install pyyaml
"""

from __future__ import annotations
import os
import sys
import re
import json
from pathlib import Path
from typing import Dict, Any, List, Tuple

try:
    import yaml
except ImportError:
    print("❌ Missing dependency: pyyaml\n   Install with:  pip install pyyaml", file=sys.stderr)
    sys.exit(2)

ROOT = Path(__file__).resolve().parents[1]   # repo root = notes-site
SCAN_DIRS = ["_posts", "_drafts"]

REQUIRED_FIELDS = [
    "title",
    "date",
    "layout",
    "categories",
    "tags",
    "published",
]

# Soft recommendations (warnings if not set as suggested)
RECOMMENDED_DEFAULTS = {
    "layout": "single",
}

# Basic date patterns Jekyll accepts. You’re using “YYYY-MM-DD HH:mm:ss Z” in Decap;
# accept ISO-like too to avoid false negatives.
DATE_PATTERNS = [
    r"^\d{4}-\d{2}-\d{2}$",
    r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}$",
    r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\s?[+-]\d{2}:?\d{2}$",
]

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n?", re.DOTALL)


def load_front_matter(text: str) -> Tuple[Dict[str, Any] | None, str]:
    """
    Returns (front_matter_dict_or_None, body_text)
    """
    m = FRONTMATTER_RE.match(text)
    if not m:
        return None, text
    raw = m.group(1)
    try:
        fm = yaml.safe_load(raw) or {}
        if not isinstance(fm, dict):
            return None, text
        body = text[m.end():]
        return fm, body
    except yaml.YAMLError:
        return None, text


def is_valid_date(s: str) -> bool:
    for pat in DATE_PATTERNS:
        if re.match(pat, s.strip()):
            return True
    return False


def validate_file(path: Path) -> Dict[str, Any]:
    issues: List[str] = []
    warnings: List[str] = []
    ok = True

    try:
        content = path.read_text(encoding="utf-8")
    except Exception as e:
        return {
            "file": str(path),
            "ok": False,
            "errors": [f"Cannot read file: {e}"],
            "warnings": [],
        }

    fm, _ = load_front_matter(content)
    if fm is None:
        return {
            "file": str(path),
            "ok": False,
            "errors": ["Missing or invalid YAML front matter (--- ... ---) at top of file."],
            "warnings": [],
        }

    # Required fields
    for key in REQUIRED_FIELDS:
        if key not in fm:
            ok = False
            issues.append(f"Missing required field: {key}")

    # Types and shapes
    if "title" in fm and not isinstance(fm["title"], str):
        ok = False
        issues.append("Field 'title' must be a string.")

    if "date" in fm:
        if not isinstance(fm["date"], (str, int, float)):
            ok = False
            issues.append("Field 'date' must be a string or number (string recommended).")
        else:
            ds = str(fm["date"])
            if not is_valid_date(ds):
                warnings.append(f"Field 'date' looks unusual for Jekyll: {ds}")

    if "layout" in fm:
        if not isinstance(fm["layout"], str):
            ok = False
            issues.append("Field 'layout' must be a string.")
        elif fm["layout"] != RECOMMENDED_DEFAULTS["layout"]:
            warnings.append(f"layout='{fm['layout']}' (recommended: '{RECOMMENDED_DEFAULTS['layout']}').")

    if "categories" in fm:
        cats = fm["categories"]
        if not (isinstance(cats, list) and all(isinstance(x, (str, int)) for x in cats)):
            ok = False
            issues.append("Field 'categories' must be a list of strings.")
        elif len(cats) == 0:
            warnings.append("Field 'categories' is an empty list (recommend at least one).")

    if "tags" in fm:
        tags = fm["tags"]
        if tags is not None and not (isinstance(tags, list) and all(isinstance(x, (str, int)) for x in tags)):
            ok = False
            issues.append("Field 'tags' must be a list of strings (or omit the field).")

    if "published" in fm and not isinstance(fm["published"], bool):
        ok = False
        issues.append("Field 'published' must be true/false.")

    return {
        "file": str(path),
        "ok": ok and not issues,
        "errors": issues,
        "warnings": warnings,
    }


def main() -> int:
    repo = ROOT
    targets: List[Path] = []
    for d in SCAN_DIRS:
        p = repo / d
        if p.exists():
            targets.extend(p.glob("*.md"))

    if not targets:
        print("ℹ️ No markdown files found in _posts/ or _drafts/ (nothing to validate).")
        return 0

    results = [validate_file(p) for p in sorted(targets)]
    errors_total = sum(1 for r in results if not r["ok"])
    warnings_total = sum(len(r["warnings"]) for r in results)

    # Pretty report
    print("\n=== FlowformLab Front-Matter Report ===")
    for r in results:
        status = "OK" if r["ok"] else "FAIL"
        print(f"\n• {r['file']}  →  {status}")
        for e in r["errors"]:
            print(f"  ❌ {e}")
        for w in r["warnings"]:
            print(f"  ⚠️  {w}")

    print("\n=== Summary ===")
    print(f"Files scanned : {len(results)}")
    print(f"Files failed  : {errors_total}")
    print(f"Warnings      : {warnings_total}")

    # machine-readable (optional)
    try:
        summary = {
            "scanned": len(results),
            "failed": errors_total,
            "warnings": warnings_total,
            "results": results,
        }
        (ROOT / "tools" / "validate_frontmatter.last.json").write_text(
            json.dumps(summary, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        print("Wrote tools/validate_frontmatter.last.json")
    except Exception as e:
        print(f"⚠️ Could not write JSON summary: {e}", file=sys.stderr)

    # Non-zero exit on any errors (good for CI/n8n gate)
    return 1 if errors_total > 0 else 0


if __name__ == "__main__":
    sys.exit(main())
