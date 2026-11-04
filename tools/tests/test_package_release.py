"""Tests for tools/package_release.py (run: python3 -m unittest discover -s tools/tests -v)."""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tools"))
import package_release as pr  # noqa: E402

MANIFEST_FILES = ["README.md", "pubspec.yaml", "lib/world/a.dart"]


def make_project(root: Path):
    """Smallest project that satisfies the ZIP's required-file list."""
    files = {
        "README.md": "readme", "pubspec.yaml": "name: x", "lib/main.dart": "void main(){}",
        "lib/game/road_game.dart": "// game", "lib/world/a.dart": "// a",
        "tools/package_release.py": "# r", "tools/packager_core.mjs": "// c",
        "FILE_MANIFEST.json": json.dumps({"files": [{"path": p} for p in MANIFEST_FILES + ["FILE_MANIFEST.json"]]}),
    }
    for rel, text in files.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")


class FakeEnv:
    """Fake runner/which so no real Flutter, npm or node is needed."""

    def __init__(self, root: Path, fail_on: str | None = None, missing: set[str] | None = None, make_apk: bool = True, apk_empty: bool = False):
        self.root, self.fail_on, self.missing = root, fail_on, missing or set()
        self.make_apk, self.apk_empty = make_apk, apk_empty
        self.commands: list[str] = []

    def which(self, tool: str):
        return None if tool in self.missing else f"/usr/bin/{tool}"

    def runner(self, cmd, cwd):
        text = " ".join(cmd)
        self.commands.append(text)
        if self.fail_on and self.fail_on in text:
            return 1
        if cmd[:3] == ["flutter", "build", "apk"] and self.make_apk:
            apk = self.root / pr.APK_RELATIVE
            apk.parent.mkdir(parents=True, exist_ok=True)
            apk.write_bytes(b"" if self.apk_empty else b"PK-fake-apk")
        return 0


class ReleaseBase(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp(prefix="trafficity_rel_"))
        self.addCleanup(shutil.rmtree, self.root, ignore_errors=True)
        make_project(self.root)
        self.out = self.root.parent / (self.root.name + ".zip")
        self.addCleanup(lambda: self.out.unlink(missing_ok=True))

    def run_release(self, env: FakeEnv, **kw):
        kw.setdefault("android_sdk", lambda: True)  # tests run without a real Android SDK; see the SDK tests below
        return pr.run_release(self.root, runner=env.runner, which=env.which, out_zip=self.out, log=lambda _m: None, **kw)


class PipelineTests(ReleaseBase):
    def test_all_steps_pass_in_the_documented_order_and_produce_a_validated_zip(self):
        env = FakeEnv(self.root)
        r = self.run_release(env)
        self.assertEqual(r.status, "READY")
        self.assertEqual(r.exit_code, 0)
        names = [s.name for s in r.steps]
        expected = ["migrate Tashkent legacy roads", "flutter pub get", "dart format check", "flutter analyze", "flutter test", "npm test",
                    "python unit tests", "CLI: validate-regions", "CLI: validate-package", "CLI: validate-bundle", "create and validate ZIP",
                    "android scaffold (only if missing)", "flutter build apk --debug", "APK exists and is non-empty"]
        self.assertEqual(names, expected)
        self.assertTrue(all(s.status in ("PASS", "SKIPPED") for s in r.steps))
        self.assertTrue(self.out.is_file())
        self.assertEqual(r.apk_size, len(b"PK-fake-apk"))
        self.assertTrue(any("flutter create" in c for c in env.commands), "scaffold must run when android/ is missing")

    def test_a_failed_flutter_step_blocks_zip_creation_and_later_steps(self):
        env = FakeEnv(self.root, fail_on="flutter analyze")
        r = self.run_release(env)
        self.assertEqual(r.status, "FAILED")
        self.assertEqual(r.exit_code, 1)
        self.assertFalse(self.out.exists())
        self.assertEqual(r.steps[-1].name, "flutter analyze")
        self.assertEqual(r.steps[-1].returncode, 1)
        self.assertFalse(any("flutter test" in c or "npm" in c or "build apk" in c for c in env.commands))

    def test_every_check_step_failure_blocks_the_zip(self):
        for marker in ["migrate_tashkent_legacy", "flutter pub get", "dart format", "flutter test", "npm test", "unittest",
                       "validate-regions", "validate-package", "validate-bundle"]:
            env = FakeEnv(self.root, fail_on=marker)
            r = self.run_release(env)
            self.assertEqual(r.status, "FAILED", marker)
            self.assertFalse(self.out.exists(), marker)

    def test_missing_flutter_binary_is_a_failure_in_strict_mode(self):
        env = FakeEnv(self.root, missing={"flutter"})
        r = self.run_release(env)
        self.assertEqual(r.status, "FAILED")
        self.assertFalse(self.out.exists())
        self.assertIn("flutter", r.steps[-1].detail)
        self.assertEqual(r.steps[-1].name, "flutter pub get")

    def test_allow_blocked_never_reports_a_release_as_ready(self):
        env = FakeEnv(self.root, missing={"flutter", "dart", "npm"})
        r = self.run_release(env, allow_blocked=True)
        self.assertEqual(r.status, "BLOCKED")
        self.assertEqual(r.exit_code, 3)
        blocked = [s.name for s in r.steps if s.status == "BLOCKED"]
        self.assertIn("flutter analyze", blocked)
        self.assertIn("APK exists and is non-empty", blocked)
        self.assertIn("NOT RELEASE-READY", pr.format_summary(r))
        self.assertTrue(self.out.exists(), "ZIP of the verified parts is still produced")

    def test_a_real_failure_is_never_downgraded_by_allow_blocked(self):
        env = FakeEnv(self.root, fail_on="flutter test", missing={"npm"})
        r = self.run_release(env, allow_blocked=True)
        self.assertEqual(r.status, "FAILED")
        self.assertFalse(self.out.exists())

    def test_apk_build_failure_removes_the_zip(self):
        env = FakeEnv(self.root, fail_on="build apk")
        r = self.run_release(env)
        self.assertEqual(r.status, "FAILED")
        self.assertFalse(self.out.exists())
        self.assertIsNone(r.zip_path)

    def test_missing_or_empty_apk_is_a_failure_even_when_the_build_command_exits_zero(self):
        for kwargs in ({"make_apk": False}, {"apk_empty": True}):
            env = FakeEnv(self.root, **kwargs)
            r = self.run_release(env)
            self.assertEqual(r.status, "FAILED", kwargs)
            self.assertEqual(r.steps[-1].name, "APK exists and is non-empty")
            self.assertFalse(self.out.exists(), kwargs)
            shutil.rmtree(self.root / "build", ignore_errors=True)

    def test_missing_android_sdk_is_a_failure_in_strict_mode_and_the_build_is_not_attempted(self):
        env = FakeEnv(self.root)
        r = self.run_release(env, android_sdk=lambda: False)
        self.assertEqual(r.status, "FAILED")
        self.assertIn("Android SDK", r.steps[-1].detail)
        self.assertEqual(r.steps[-1].name, "flutter build apk --debug")
        self.assertFalse(any(c.startswith("flutter build apk") for c in env.commands))
        self.assertFalse(self.out.exists())

    def test_missing_android_sdk_is_blocked_with_allow_blocked_and_never_release_ready(self):
        env = FakeEnv(self.root)
        r = self.run_release(env, android_sdk=lambda: False, allow_blocked=True)
        self.assertEqual(r.status, "BLOCKED")
        self.assertEqual(r.exit_code, 3)
        by_name = {s.name: s for s in r.steps}
        self.assertEqual(by_name["flutter build apk --debug"].status, "BLOCKED")
        self.assertEqual(by_name["APK exists and is non-empty"].status, "BLOCKED")
        self.assertFalse(any(c.startswith("flutter build apk") for c in env.commands))
        self.assertTrue(self.out.exists())

    def test_android_sdk_detection_uses_existing_directories_only(self):
        self.assertFalse(pr._android_sdk_available({}))
        self.assertFalse(pr._android_sdk_available({"ANDROID_HOME": str(self.root / "nope")}))
        self.assertTrue(pr._android_sdk_available({"ANDROID_SDK_ROOT": str(self.root)}))
        self.assertTrue(pr._android_sdk_available({"ANDROID_HOME": str(self.root)}))

    def test_scaffold_removes_the_generated_widget_test_but_keeps_an_existing_one(self):
        class Env(FakeEnv):
            def runner(inner, cmd, cwd):
                if cmd[:2] == ["flutter", "create"]:
                    (self.root / "test").mkdir(exist_ok=True)
                    wt = self.root / "test" / "widget_test.dart"
                    if not wt.exists():                  # `flutter create .` never overwrites existing files
                        wt.write_text("// generated counter test")
                return super().runner(cmd, cwd)

        r = self.run_release(Env(self.root))
        self.assertEqual(r.status, "READY")
        self.assertFalse((self.root / "test" / "widget_test.dart").exists())
        shutil.rmtree(self.root / "build", ignore_errors=True)
        (self.root / "test").mkdir(exist_ok=True)
        (self.root / "test" / "widget_test.dart").write_text("// the project's own test")
        r = self.run_release(Env(self.root))
        self.assertEqual(r.status, "READY")
        self.assertEqual((self.root / "test" / "widget_test.dart").read_text(), "// the project's own test")

    def test_scaffold_is_skipped_when_android_project_exists(self):
        (self.root / "android/app").mkdir(parents=True)
        (self.root / "android/app/build.gradle").write_text("// gradle")
        env = FakeEnv(self.root)
        r = self.run_release(env)
        self.assertEqual(r.status, "READY")
        self.assertFalse(any("flutter create" in c for c in env.commands))
        self.assertEqual(next(s for s in r.steps if s.name.startswith("android scaffold")).status, "SKIPPED")

    def test_zip_is_built_before_scaffolding_so_generated_files_never_enter_it(self):
        env = FakeEnv(self.root)
        r = self.run_release(env)
        names = [s.name for s in r.steps]
        self.assertLess(names.index("create and validate ZIP"), names.index("android scaffold (only if missing)"))

    def test_summary_reports_commands_exit_codes_and_digest(self):
        env = FakeEnv(self.root)
        r = self.run_release(env)
        text = pr.format_summary(r)
        self.assertIn("rc=0", text)
        self.assertIn(r.zip_sha256, text)
        self.assertIn("RELEASE READY", text)


class ZipTests(ReleaseBase):
    def add_junk(self):
        for rel in [".env", "secrets/token.pat", "a/__pycache__/x.pyc", "node_modules/m/i.js", "local.properties", ".git/config",
                    "build/out.bin", ".dart_tool/x", "old.zip", ".DS_Store", ".gradle/g"]:
            p = self.root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text("junk")

    def test_required_files_present_and_excluded_files_absent(self):
        self.add_junk()
        count, digest, size = pr.build_zip(self.root, self.out)
        with zipfile.ZipFile(self.out) as zf:
            names = set(zf.namelist())
        for rel in pr.required_paths(self.root):
            if rel == "FILE_MANIFEST.json" or (self.root / rel).exists():
                self.assertIn(f"Trafficity/{rel}", names)
        for bad in [".env", "token.pat", "__pycache__", "node_modules", "local.properties", ".git/", "build/", ".dart_tool", "old.zip", ".DS_Store", ".gradle"]:
            self.assertFalse(any(bad in n for n in names), bad)
        self.assertEqual(count, len(names))
        self.assertEqual(hashlib.sha256(self.out.read_bytes()).hexdigest(), digest)
        self.assertEqual(self.out.stat().st_size, size)
        self.assertEqual(pr.validate_zip(self.root, self.out), [])

    def test_zip_never_contains_itself(self):
        inside = self.root / pr.ZIP_NAME
        count, *_ = pr.build_zip(self.root, inside)
        with zipfile.ZipFile(inside) as zf:
            self.assertFalse(any(n.endswith(".zip") for n in zf.namelist()))
        pr.build_zip(self.root, inside)  # second run replaces the old ZIP without including it
        with zipfile.ZipFile(inside) as zf:
            self.assertFalse(any(n.endswith(".zip") for n in zf.namelist()))

    def test_repeated_packaging_gives_identical_bytes_even_when_mtimes_change(self):
        _, d1, _ = pr.build_zip(self.root, self.out)
        later = time.time() + 5000
        for p in self.root.rglob("*"):
            if p.is_file():
                os.utime(p, (later, later))
        _, d2, _ = pr.build_zip(self.root, self.out)
        self.assertEqual(d1, d2)

    def test_entries_are_sorted_with_fixed_timestamps_and_permissions(self):
        pr.build_zip(self.root, self.out)
        with zipfile.ZipFile(self.out) as zf:
            infos = zf.infolist()
        self.assertEqual([i.filename for i in infos], sorted(i.filename for i in infos))
        self.assertTrue(all(i.date_time == pr.FIXED_DATE for i in infos))
        self.assertTrue(all((i.external_attr >> 16) == 0o100644 for i in infos))

    def test_validation_detects_a_missing_required_file_and_a_corrupt_zip(self):
        (self.root / "lib/main.dart").unlink()
        pr.build_zip(self.root, self.out)
        self.assertTrue(any("lib/main.dart" in p for p in pr.validate_zip(self.root, self.out)))
        self.out.write_bytes(b"not a zip")
        self.assertTrue(any("cannot be opened" in p for p in pr.validate_zip(self.root, self.out)))

    @unittest.skipUnless(shutil.which("git"), "git not installed")
    def test_git_mode_includes_tracked_and_untracked_but_not_ignored_files(self):
        run = lambda *a: subprocess.run(["git", *a], cwd=self.root, check=True, capture_output=True)
        run("init", "-q")
        (self.root / ".gitignore").write_text("ignored_dir/\n*.secret\n")
        (self.root / "ignored_dir").mkdir()
        (self.root / "ignored_dir/x.txt").write_text("x")
        (self.root / "k.secret").write_text("s")
        (self.root / "untracked_new.txt").write_text("new")
        run("add", "README.md", "pubspec.yaml", ".gitignore")
        files = pr.collect_files(self.root)
        self.assertIn("untracked_new.txt", files)
        self.assertIn("README.md", files)
        self.assertNotIn("ignored_dir/x.txt", files)
        self.assertNotIn("k.secret", files)
        self.assertFalse(any(f.startswith(".git/") for f in files))


class RealRepositoryTests(unittest.TestCase):
    def test_real_repository_zip_contains_every_manifest_file(self):
        tmp = Path(tempfile.mkdtemp(prefix="trafficity_realzip_"))
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        out = tmp / "t.zip"
        count, digest, _ = pr.build_zip(REPO, out)
        self.assertEqual(pr.validate_zip(REPO, out), [])
        manifest = json.loads((REPO / "FILE_MANIFEST.json").read_text(encoding="utf-8"))
        with zipfile.ZipFile(out) as zf:
            names = set(zf.namelist())
        self.assertEqual(len(manifest["files"]), 55)
        for f in manifest["files"]:
            self.assertIn(f"Trafficity/{f['path']}", names)
        _, digest2, _ = pr.build_zip(REPO, out)
        self.assertEqual(digest, digest2)

    def test_steps_use_no_silent_skip_flags(self):
        source = (REPO / "tools" / "package_release.py").read_text(encoding="utf-8")
        self.assertNotIn("allow_missing_binary", source)
        self.assertNotIn("continue-on-error", source)


if __name__ == "__main__":
    unittest.main()
