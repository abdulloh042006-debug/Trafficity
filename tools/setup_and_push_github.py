#!/usr/bin/env python3
"""
setup_and_push_github.py — Trafficity Uzbekistan-Wide Expansion GitHub Automator.
"""

from __future__ import annotations
import argparse
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]


def run_cmd(cmd: list[str], check: bool = True) -> int:
    print(f"\n$ {' '.join(cmd)}")
    res = subprocess.run(cmd, cwd=REPO_ROOT, check=False)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}")
    return res.returncode


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Prepare, test, package ZIP, and push Trafficity Uzbekistan expansion to GitHub."
    )
    parser.add_argument(
        "--branch",
        default="codex/uzbekistan-expansion",
        help="Git feature branch name (default: codex/uzbekistan-expansion)",
    )
    parser.add_argument(
        "--push",
        action="store_true",
        help="Automatically run 'git push -u origin <branch>'",
    )
    args = parser.parse_args()

    run_cmd([sys.executable, "tools/package_release.py"], check=True)
    run_cmd(["git", "checkout", "-B", args.branch], check=True)
    run_cmd(["git", "diff", "--check"], check=True)
    run_cmd(
        [
            "git",
            "add",
            "pubspec.yaml",
            "UZBEKISTAN_EXPANSION_README.md",
            "lib/world",
            "lib/ui",
            "assets/world/uzbekistan",
            "tools/map/trafficity_ingest.py",
            "tools/map/migrate_tashkent_legacy.py",
            "tools/package_release.py",
            "tools/setup_and_push_github.py",
            "test/uzbekistan_world_test.dart",
        ],
        check=True,
    )
    run_cmd(
        [
            "git",
            "commit",
            "-m",
            "feat(uzbekistan): expand Trafficity to 14-region Uzbekistan 2D/3D platform",
        ],
        check=False,
    )
    if args.push:
        run_cmd(["git", "push", "-u", "origin", args.branch], check=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
