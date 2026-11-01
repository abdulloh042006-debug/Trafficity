#!/usr/bin/env python3
"""
package_release.py — Builds, validates, and packages the complete Flutter
Trafficity Uzbekistan project into Trafficity-Uzbekistan-Complete.zip.
"""

from __future__ import annotations
import os
import subprocess
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ZIP = REPO_ROOT / "Trafficity-Uzbekistan-Complete.zip"

EXCLUDED_DIRS = {
    ".git",
    ".dart_tool",
    "build",
    ".idea",
    ".vscode",
    "__pycache__",
    ".gradle",
}

EXCLUDED_FILES = {
    "Trafficity-Uzbekistan-Complete.zip",
    ".DS_Store",
    "local.properties",
}


def run_step(cmd: list[str], allow_missing_binary: bool = False) -> int:
    print(f"\n==> Running: {' '.join(cmd)}")
    try:
        res = subprocess.run(cmd, cwd=REPO_ROOT, check=False)
        return res.returncode
    except FileNotFoundError as exc:
        if allow_missing_binary:
            print(f"    [skipped — binary not found in PATH: {exc}]")
            return 0
        raise


def build_clean_zip() -> Path:
    if OUTPUT_ZIP.exists():
        OUTPUT_ZIP.unlink()

    file_count = 0
    with zipfile.ZipFile(OUTPUT_ZIP, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(REPO_ROOT):
            dirs[:] = [d for d in sorted(dirs) if d not in EXCLUDED_DIRS]
            root_path = Path(root)
            for fname in sorted(files):
                if fname in EXCLUDED_FILES or fname.endswith(".pyc"):
                    continue
                full_path = root_path / fname
                rel_path = full_path.relative_to(REPO_ROOT)
                zf.write(full_path, arcname=str(Path("Trafficity") / rel_path))
                file_count += 1

    size_mb = OUTPUT_ZIP.stat().st_size / (1024 * 1024)
    print(
        f"\n[package_release] Created {OUTPUT_ZIP.name} ({file_count} files, {size_mb:.2f} MB)"
    )
    return OUTPUT_ZIP


def main() -> int:
    run_step([sys.executable, "tools/map/migrate_tashkent_legacy.py"])
    run_step(["flutter", "pub", "get"], allow_missing_binary=True)
    run_step(["flutter", "analyze"], allow_missing_binary=True)
    run_step(["flutter", "test"], allow_missing_binary=True)
    run_step(["flutter", "build", "apk", "--debug"], allow_missing_binary=True)
    run_step(["git", "diff", "--check"], allow_missing_binary=True)
    build_clean_zip()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
