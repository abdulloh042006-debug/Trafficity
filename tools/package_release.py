#!/usr/bin/env python3
"""
package_release.py - strict release pipeline for the Trafficity Uzbekistan expansion.

Runs, in order, and stops at the first failure (no ZIP is produced after a failed step):
  migration -> flutter pub get -> format check -> flutter analyze -> flutter test -> npm test -> python tests
  -> CLI validation -> ZIP (deterministic, re-opened and validated) -> Android scaffold (only if missing)
  -> flutter build apk --debug -> APK exists and is non-empty.

Strict by default: a required tool that is not installed FAILS the release (exit 1). With --allow-blocked the step is
recorded as BLOCKED instead; the ZIP is still produced but the run ends with exit 3 and "NOT RELEASE-READY".
If the APK step fails, the ZIP that was already written is deleted: nothing is delivered from a failed release.

Exit codes: 0 release ready | 1 failure | 3 completed with BLOCKED steps (not release-ready).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

REPO_ROOT = Path(__file__).resolve().parents[1]
ZIP_NAME = "Trafficity-Uzbekistan-Complete.zip"
ZIP_PREFIX = "Trafficity"
APK_RELATIVE = Path("build/app/outputs/flutter-apk/app-debug.apk")

EXCLUDED_DIRS = {".git", ".dart_tool", "build", ".idea", ".vscode", "__pycache__", ".gradle", "node_modules", ".pub-cache"}
EXCLUDED_NAMES = {".DS_Store", "local.properties", ".env"}
EXCLUDED_SUFFIXES = (".pyc", ".pat", ".zip", ".keystore.local")
FIXED_DATE = (1980, 1, 1, 0, 0, 0)

# Present in every release ZIP in addition to everything listed in FILE_MANIFEST.json.
REQUIRED_EXTRA = ("pubspec.yaml", "lib/main.dart", "lib/game/road_game.dart", "tools/package_release.py", "tools/packager_core.mjs")


@dataclass
class Step:
    name: str
    cmd: list[str] | None = None  # None = internal step handled by the pipeline
    tool: str | None = None       # executable that must exist (looked up with `which`)
    kind: str = "check"           # check | zip | scaffold | apk | apk_check


@dataclass
class StepResult:
    name: str
    status: str                   # PASS | FAIL | BLOCKED | SKIPPED
    command: str = ""
    returncode: int | None = None
    detail: str = ""
    seconds: float = 0.0


@dataclass
class ReleaseResult:
    status: str                   # READY | FAILED | BLOCKED
    steps: list[StepResult] = field(default_factory=list)
    zip_path: Path | None = None
    zip_sha256: str = ""
    zip_size: int = 0
    zip_files: int = 0
    apk_path: Path | None = None
    apk_size: int = 0

    @property
    def exit_code(self) -> int:
        return {"READY": 0, "FAILED": 1, "BLOCKED": 3}[self.status]


Runner = Callable[[list[str], Path], int]


def subprocess_runner(cmd: list[str], cwd: Path) -> int:
    return subprocess.run(cmd, cwd=cwd, check=False).returncode


def default_steps() -> list[Step]:
    py = sys.executable
    return [
        Step("migrate Tashkent legacy roads", [py, "tools/map/migrate_tashkent_legacy.py"], py),
        Step("flutter pub get", ["flutter", "pub", "get"], "flutter"),
        Step("dart format check", ["dart", "format", "--output=none", "--set-exit-if-changed", "lib", "test"], "dart"),
        Step("flutter analyze", ["flutter", "analyze"], "flutter"),
        Step("flutter test", ["flutter", "test"], "flutter"),
        Step("npm test", ["npm", "test"], "npm"),
        Step("python unit tests", [py, "-m", "unittest", "discover", "-s", "tools/tests"], py),
        Step("CLI: validate-regions", ["node", "tools/uzbekistan_pack_cli.mjs", "validate-regions"], "node"),
        Step("CLI: validate-package", ["node", "tools/uzbekistan_pack_cli.mjs", "validate-package",
                                       "assets/world/uzbekistan/regions/tashkent_city/manifest.json"], "node"),
        Step("CLI: validate-bundle", ["node", "tools/uzbekistan_pack_cli.mjs", "validate-bundle"], "node"),
        Step("create and validate ZIP", None, None, "zip"),
        Step("android scaffold (only if missing)", ["flutter", "create", "--platforms=android", "--org", "uz.abdulloh", "."], "flutter", "scaffold"),
        Step("flutter build apk --debug", ["flutter", "build", "apk", "--debug"], "flutter", "apk"),
        Step("APK exists and is non-empty", None, None, "apk_check"),
    ]


# ----------------------------------------------------------------------------- ZIP

def _git_files(root: Path) -> list[str] | None:
    """Tracked + untracked-not-ignored files, or None when `root` is not a usable git work tree."""
    if shutil.which("git") is None or not (root / ".git").exists():
        return None
    try:
        out = subprocess.run(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"],
                             cwd=root, check=True, capture_output=True).stdout
    except (subprocess.CalledProcessError, OSError):
        return None
    return [p for p in out.decode("utf-8").split("\0") if p]


def _is_excluded(rel: str) -> bool:
    parts = rel.split("/")
    if any(p in EXCLUDED_DIRS for p in parts[:-1]):
        return True
    name = parts[-1]
    return name in EXCLUDED_NAMES or name.endswith(EXCLUDED_SUFFIXES)


def collect_files(root: Path) -> list[str]:
    """Sorted relative POSIX paths for the ZIP. Always applies the exclusion rules, with or without git."""
    listed = _git_files(root)
    if listed is None:
        listed = []
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in EXCLUDED_DIRS]
            for fname in filenames:
                listed.append((Path(dirpath) / fname).relative_to(root).as_posix())
    return sorted({p for p in listed if not _is_excluded(p) and (root / p).is_file()})


def required_paths(root: Path) -> list[str]:
    paths = list(REQUIRED_EXTRA)
    manifest = root / "FILE_MANIFEST.json"
    if manifest.is_file():
        paths += [f["path"] for f in json.loads(manifest.read_text(encoding="utf-8"))["files"]]
    return sorted(set(paths))


def build_zip(root: Path, out: Path) -> tuple[int, str, int]:
    """Writes a deterministic ZIP (sorted entries, fixed timestamps and permissions). Returns (files, sha256, size)."""
    files = collect_files(root)
    out = Path(out)
    if out.exists():
        out.unlink()
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for rel in files:
            info = zipfile.ZipInfo(f"{ZIP_PREFIX}/{rel}", date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o100644 << 16)
            info.create_system = 3
            zf.writestr(info, (root / rel).read_bytes())
    data = out.read_bytes()
    return len(files), hashlib.sha256(data).hexdigest(), len(data)


def validate_zip(root: Path, out: Path) -> list[str]:
    """Re-opens the ZIP and checks structure, CRCs, required files and forbidden content. Returns problems."""
    problems: list[str] = []
    try:
        with zipfile.ZipFile(out) as zf:
            bad = zf.testzip()
            if bad:
                problems.append(f"corrupt entry: {bad}")
            names = zf.namelist()
    except (zipfile.BadZipFile, OSError) as exc:
        return [f"ZIP cannot be opened: {exc}"]
    have = {n[len(ZIP_PREFIX) + 1:] for n in names if n.startswith(ZIP_PREFIX + "/")}
    if len(have) != len(names):
        problems.append("entries outside the project prefix or duplicate entries")
    for req in required_paths(root):
        if req not in have:
            problems.append(f"required file missing from ZIP: {req}")
    for rel in sorted(have):
        if _is_excluded(rel):
            problems.append(f"excluded file present in ZIP: {rel}")
    if names != sorted(names):
        problems.append("entries are not sorted")
    return problems


# ----------------------------------------------------------------------------- pipeline

def _android_present(root: Path) -> bool:
    return (root / "android" / "app" / "build.gradle").exists() or (root / "android" / "app" / "build.gradle.kts").exists()


def run_release(
    root: Path = REPO_ROOT,
    runner: Runner = subprocess_runner,
    which: Callable[[str], str | None] = shutil.which,
    allow_blocked: bool = False,
    out_zip: Path | None = None,
    steps: list[Step] | None = None,
    log: Callable[[str], None] = print,
) -> ReleaseResult:
    root = Path(root)
    out_zip = Path(out_zip) if out_zip else root / ZIP_NAME
    result = ReleaseResult(status="READY")
    blocked = False

    def record(r: StepResult) -> None:
        result.steps.append(r)
        log(f"[{r.status}] {r.name}" + (f" - {r.detail}" if r.detail else ""))

    def fail(name: str, detail: str, command: str = "", rc: int | None = None, seconds: float = 0.0) -> ReleaseResult:
        record(StepResult(name, "FAIL", command, rc, detail, seconds))
        result.status = "FAILED"
        return result

    for step in (steps if steps is not None else default_steps()):
        if step.kind == "zip":
            started = time.time()
            count, digest, size = build_zip(root, out_zip)
            problems = validate_zip(root, out_zip)
            if problems:
                out_zip.unlink(missing_ok=True)
                return fail(step.name, "; ".join(problems[:5]), seconds=time.time() - started)
            result.zip_path, result.zip_sha256, result.zip_size, result.zip_files = out_zip, digest, size, count
            record(StepResult(step.name, "PASS", detail=f"{count} files, {size} bytes, sha256={digest}", seconds=time.time() - started))
            continue

        if step.kind == "apk_check":
            apk = root / APK_RELATIVE
            if any(s.name == "flutter build apk --debug" and s.status == "BLOCKED" for s in result.steps):
                record(StepResult(step.name, "BLOCKED", detail="APK build was blocked, so no APK exists"))
                continue
            if not apk.is_file() or apk.stat().st_size == 0:
                if result.zip_path:
                    result.zip_path.unlink(missing_ok=True)
                    result.zip_path = None
                return fail(step.name, f"{APK_RELATIVE} is missing or empty; the ZIP was removed")
            result.apk_path, result.apk_size = apk, apk.stat().st_size
            record(StepResult(step.name, "PASS", detail=f"{APK_RELATIVE} ({result.apk_size} bytes)"))
            continue

        if step.kind == "scaffold" and _android_present(root):
            record(StepResult(step.name, "SKIPPED", detail="android/ project files already exist"))
            continue

        command = " ".join(step.cmd or [])
        if step.tool and which(step.tool) is None:
            if allow_blocked:
                blocked = True
                record(StepResult(step.name, "BLOCKED", command, None, f"required tool not found: {step.tool}"))
                continue
            return fail(step.name, f"required tool not found: {step.tool} (use --allow-blocked to continue without it)", command)

        started = time.time()
        rc = runner(step.cmd or [], root)
        elapsed = time.time() - started
        if rc != 0:
            if step.kind == "apk" and result.zip_path:
                result.zip_path.unlink(missing_ok=True)
                result.zip_path = None
            return fail(step.name, f"exit code {rc}", command, rc, elapsed)
        record(StepResult(step.name, "PASS", command, rc, "", elapsed))

    if blocked:
        result.status = "BLOCKED"
    return result


def format_summary(r: ReleaseResult) -> str:
    lines = ["", "==== release summary ===="]
    for s in r.steps:
        lines.append(f"{s.status:8} {s.name}" + (f"  [{s.command}] rc={s.returncode}" if s.command else ""))
    if r.zip_path:
        lines += [f"ZIP      : {r.zip_path}", f"ZIP size : {r.zip_size} bytes", f"ZIP files: {r.zip_files}", f"ZIP sha256: {r.zip_sha256}"]
    if r.apk_path:
        lines.append(f"APK      : {r.apk_path} ({r.apk_size} bytes)")
    lines.append({"READY": "RESULT: RELEASE READY (every step passed)",
                  "FAILED": "RESULT: FAILED - no release was produced",
                  "BLOCKED": "RESULT: NOT RELEASE-READY - some steps were BLOCKED (tools missing); nothing was verified for them"}[r.status])
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Strict Trafficity Uzbekistan release pipeline")
    ap.add_argument("--allow-blocked", action="store_true", help="record missing tools as BLOCKED instead of failing (result is never release-ready)")
    ap.add_argument("--out", type=Path, default=None, help=f"output ZIP (default: ./{ZIP_NAME})")
    args = ap.parse_args(argv)
    result = run_release(allow_blocked=args.allow_blocked, out_zip=args.out)
    print(format_summary(result))
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
