"""Tests for the Chromium security-update tools. Run: /opt/homebrew/bin/python3.12 -m unittest discover -s Tools/chromium"""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


update = load("security-update")
rebase = load("rebase-patches")
fetch = load("fetch-source")
toolchains = load("prepare-toolchains")

LOCK = {"schema_version": 1, "chromium_version": "157.0.8103.51", "storage_root": "/Volumes/BoazBuild/cef/direct",
        "archive_name": "chromium-157.0.8103.51-lite.tar.xz", "archive_root": "chromium-157.0.8103.51"}
SHA = "c66efa0eb499713d018493e1973155a057576435a7e5d5ed0e5ca131b2ae3019"


class Bump(unittest.TestCase):
    def test_pins_the_new_archive_and_keeps_the_rest(self):
        lock = update.bumped(LOCK, "159.0.8154.40", SHA)
        self.assertEqual(lock["chromium_version"], "159.0.8154.40")
        self.assertEqual(lock["archive_url"], "https://commondatastorage.googleapis.com/chromium-browser-official/"
                                              "chromium-159.0.8154.40-lite.tar.xz")
        self.assertEqual(lock["archive_root"], "chromium-159.0.8154.40")
        self.assertEqual(lock["archive_sha256"], SHA)
        self.assertEqual(lock["storage_root"], LOCK["storage_root"])

    def test_refuses_an_older_or_equal_version(self):
        for version in ("157.0.8103.51", "157.0.8103.9", "156.9.9999.99"):
            with self.assertRaises(ValueError):
                update.bumped(LOCK, version, SHA)

    def test_refuses_a_bad_checksum_or_version(self):
        with self.assertRaises(ValueError):
            update.bumped(LOCK, "159.0.8154.40", "abc")
        with self.assertRaises(ValueError):
            update.bumped(LOCK, "159.0", SHA)

    def test_reads_googles_hashes_file(self):
        name = "chromium-157.0.8103.51-lite.tar.xz"
        text = f"md5  3c2544c5ef54a1805ced176d0a821e3f  {name}\nsha256  {SHA.upper()}  {name}\n"
        self.assertEqual(update.parse_hashes(text, name), SHA)
        with self.assertRaises(ValueError):
            update.parse_hashes(text, "chromium-1.2.3.4-lite.tar.xz")


class Runner(unittest.TestCase):
    def test_plan_follows_the_runbook(self):
        steps = update.plan("/python", 6)
        self.assertEqual([s[0] for s in steps], ["bump", "fetch", "toolchains-check", "rebase", "commit", "apply",
                                                 "toolchains", "objdump", "host", "build", "pack"])
        self.assertEqual(steps[-2][3][-3:], ["--build", "--jobs", "6"])

    def test_stops_at_the_first_failure_and_times_every_step(self):
        ran, saves = [], []
        def ok(args):
            ran.append("ok")
        def broken(args):
            ran.append("broken")
            raise ValueError("no")
        def never(args):
            ran.append("never")
        ticks = iter(range(100))
        receipt = {"steps": [], "status": "running", "ended": None}
        update.run([("one", "B", "dev", ok), ("two", "P", "dev", broken), ("three", "C", "dev", never)],
                   None, receipt, lambda value: saves.append(json.dumps(value)),
                   clock=lambda: next(ticks) * 10.0, stamp=lambda: "t")
        self.assertEqual(ran, ["ok", "broken"])
        self.assertEqual(receipt["status"], "failed")
        self.assertEqual([(s["id"], s["exit"], s["seconds"]) for s in receipt["steps"]],
                         [("one", 0, 10.0), ("two", 1, 10.0)])
        self.assertEqual(json.loads(saves[-1]), receipt)

    def test_a_clean_run_is_ok(self):
        receipt = {"steps": [], "status": "running", "ended": None}
        update.run([("one", "B", "dev", lambda args: None)], None, receipt, lambda value: None)
        self.assertEqual(receipt["status"], "ok")


PATCH_ONE = """--- a/a/file.txt
+++ b/a/file.txt
@@ -3,3 +3,3 @@
 one
-two
+TWO
 three
"""
PATCH_TWO = """--- a/a/file.txt
+++ b/a/file.txt
@@ -4,3 +4,3 @@
 TWO
-three
+THREE
 c
"""
UPSTREAM = "zero\na\nb\none\ntwo\nthree\nc\n"  # a line above the patched lines moved them down


@unittest.skipUnless(Path(rebase.GIT).exists(), "needs Homebrew git")
class Rebase(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, self.dir)
        (self.dir / "scripts/patches").mkdir(parents=True)
        (self.dir / "scripts/patches/one.patch").write_text(PATCH_ONE)
        (self.dir / "scripts/patches/two.patch").write_text(PATCH_TWO)
        (self.dir / "src/a").mkdir(parents=True)
        self.manifest = {"chromium_version": "1.0.0.0", "patches": [
            {"file": "patches/one.patch", "sha256": "old", "files": [{"path": "a/file.txt", "before": "x", "after": "y"}]},
            {"file": "patches/two.patch", "sha256": "old", "files": [{"path": "a/file.txt", "before": "y", "after": "z"}]}]}

    def run_rebase(self):
        work = self.dir / "work"
        shutil.rmtree(work, ignore_errors=True)
        work.mkdir()
        return rebase.rebase(self.manifest, "2.0.0.0", self.dir / "src", self.dir / "scripts", work)

    def test_chains_clean_applies_and_rewrites_hashes(self):
        (self.dir / "src/a/file.txt").write_text(UPSTREAM)
        manifest, conflicts = self.run_rebase()
        self.assertEqual(conflicts, [])
        one, two = manifest["patches"]
        sha = lambda text: rebase.sha(text.encode())
        self.assertEqual(manifest["chromium_version"], "2.0.0.0")
        self.assertEqual(one["sha256"], sha(PATCH_ONE))
        self.assertEqual(one["files"], [{"path": "a/file.txt", "before": sha(UPSTREAM),
                                         "after": sha(UPSTREAM.replace("two", "TWO"))}])
        self.assertEqual(two["files"][0]["before"], one["files"][0]["after"])
        self.assertEqual(two["files"][0]["after"], sha(UPSTREAM.replace("two", "TWO").replace("three", "THREE")))
        self.assertEqual((self.dir / "src/a/file.txt").read_text(), UPSTREAM)

    def test_lists_conflicts_and_keeps_their_old_entries(self):
        (self.dir / "src/a/file.txt").write_text(UPSTREAM.replace("two", "changed"))
        manifest, conflicts = self.run_rebase()
        self.assertEqual([c["patch"] for c in conflicts], ["patches/one.patch", "patches/two.patch"])
        self.assertEqual(manifest["patches"], self.manifest["patches"])

    def test_a_file_missing_upstream_is_a_conflict(self):
        manifest, conflicts = self.run_rebase()
        self.assertIn("missing in the new tree: a/file.txt", conflicts[0]["error"])


class Trees(unittest.TestCase):
    def setUp(self):
        self.root = Path(tempfile.mkdtemp()).resolve()
        self.addCleanup(shutil.rmtree, self.root)
        (self.root / "chromium/src/chrome").mkdir(parents=True)
        (self.root / "chromium/src/chrome/VERSION").write_text("MAJOR=157\nMINOR=0\nBUILD=8103\nPATCH=51\n")
        (self.root / "patches-applied.json").write_text("{}")
        (self.root / "toolchains").mkdir()

    def test_retiring_keeps_the_tree_and_its_receipts(self):
        self.assertEqual(fetch.tree_version(self.root / "chromium/src"), "157.0.8103.51")
        fetch.retire(self.root, "157.0.8103.51")
        keep = self.root / "previous/157.0.8103.51"
        self.assertTrue((keep / "chromium/src/chrome/VERSION").is_file())
        self.assertTrue((keep / "patches-applied.json").is_file())
        self.assertTrue((keep / "toolchains").is_dir())
        self.assertFalse((self.root / "chromium").exists())

    def test_retiring_never_overwrites(self):
        (self.root / "previous/157.0.8103.51").mkdir(parents=True)
        (self.root / "previous/157.0.8103.51/patches-applied.json").write_text("kept")
        with self.assertRaises(ValueError):
            fetch.retire(self.root, "157.0.8103.51")
        self.assertTrue((self.root / "chromium/src").is_dir())

    def test_toolchain_drift_names_pins_missing_from_deps(self):
        source = self.root / "chromium/src"
        for name in toolchains.DEPS_FILES:
            (source / name).parent.mkdir(parents=True, exist_ok=True)
            (source / name).write_text("")
        (source / "DEPS").write_text("'object_name': 'Mac_arm64/clang-1.tar.xz', 'sha256sum': 'aa',\n"
                                     "'version': 'git_revision:1234',\n")
        lock = {"gcs": [{"id": "clang", "bucket": "b", "object": "Mac_arm64/clang-1.tar.xz", "sha256": "aa"},
                        {"id": "rust", "bucket": "b", "object": "Mac_arm64/rust-2.tar.xz", "sha256": "bb"}],
                "cipd": [{"id": "gn", "version": "git_revision:1234"}]}
        self.assertEqual(toolchains.deps_drift(lock, source),
                         ["rust: Mac_arm64/rust-2.tar.xz", "rust: bb"])


if __name__ == "__main__":
    unittest.main()
