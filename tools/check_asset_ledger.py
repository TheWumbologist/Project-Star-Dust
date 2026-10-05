#!/usr/bin/env python3
"""Fails if any file under assets/ is missing from assets/ASSET_LEDGER.csv,
or if AI-tagging rules are broken.

Rules (from the GDD, "Assets, licensing and AI tagging"):
  - every asset has a ledger row: path, source, author, license, ai_generated, tool, notes
  - AI-generated assets live under assets/_ai_generated/ and end in __AI
  - ledger rows marked ai_generated=yes must follow both of the above

Usage: python3 tools/check_asset_ledger.py   (exit code 1 on problems)
"""
import csv
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
LEDGER = ASSETS / "ASSET_LEDGER.csv"
COLUMNS = ["path", "source", "author", "license", "ai_generated", "tool", "notes"]
# Godot sidecar files and the ledger itself are not assets.
IGNORED_SUFFIXES = {".import", ".uid"}
IGNORED_NAMES = {"ASSET_LEDGER.csv", ".gitkeep"}


def main() -> int:
    problems = []
    with LEDGER.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != COLUMNS:
            problems.append(f"ledger header must be: {','.join(COLUMNS)}")
        rows = {row["path"]: row for row in reader}

    files = sorted(
        p.relative_to(ROOT).as_posix()
        for p in ASSETS.rglob("*")
        if p.is_file() and p.suffix not in IGNORED_SUFFIXES and p.name not in IGNORED_NAMES
    )

    for path in files:
        stem = Path(path).stem
        in_ai_folder = path.startswith("assets/_ai_generated/")
        if path not in rows:
            problems.append(f"missing from ledger: {path}")
        if in_ai_folder and not stem.endswith("__AI"):
            problems.append(f"file in _ai_generated/ must end in __AI: {path}")
        if stem.endswith("__AI") and not in_ai_folder:
            problems.append(f"__AI file must live under assets/_ai_generated/: {path}")

    for path, row in rows.items():
        if not (ROOT / path).is_file():
            problems.append(f"ledger row points at a missing file: {path}")
        if row.get("ai_generated", "").strip().lower() == "yes":
            if not path.startswith("assets/_ai_generated/") or not Path(path).stem.endswith("__AI"):
                problems.append(f"ai_generated=yes but not tagged by folder and __AI suffix: {path}")

    for p in problems:
        print(f"ASSET LEDGER: {p}")
    if problems:
        return 1
    print(f"Asset ledger OK ({len(files)} assets).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
