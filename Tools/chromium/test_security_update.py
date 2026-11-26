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
        return rebase.rebase(self.manifest, "2.0.0.0", self.dir / "src", self.dir / "scripts", work)[:2]

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

    def test_lists_patched_files_that_changed_upstream(self):
        (self.dir / "src/a/file.txt").write_text(UPSTREAM)
        manifest, _ = self.run_rebase()
        self.manifest = manifest  # the same tree again: nothing changed under the patches
        work = self.dir / "work"
        shutil.rmtree(work)
        work.mkdir()
        self.assertEqual(rebase.rebase(manifest, "2.0.0.0", self.dir / "src", self.dir / "scripts", work)[2], [])
        (self.dir / "src/a/file.txt").write_text("new\n" + UPSTREAM)
        shutil.rmtree(work)
        work.mkdir()
        review = rebase.rebase(manifest, "2.0.0.1", self.dir / "src", self.dir / "scripts", work)[2]
        self.assertEqual(review, [{"patch": "patches/one.patch", "path": "a/file.txt"},
                                  {"patch": "patches/two.patch", "path": "a/file.txt"}])

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



class ToolchainDrift(unittest.TestCase):
    LOCK = {"gcs": [{"id": "clang", "destination": "third_party/llvm-build/Release+Asserts", "bucket": "b",
                     "object": "Mac_arm64/clang-1.tar.xz", "sha256": "aa", "size_bytes": 5}],
            "cipd": [{"id": "gn", "destination": "buildtools/mac", "package": "gn/gn/mac-arm64",
                      "version": "git_revision:1234"},
                     {"id": "go", "destination": "third_party/dawn/tools/golang/mac-arm64",
                      "package": "infra/3pp/tools/go/mac-arm64", "version": "version:3@1.0"}]}
    ROOT = """
vars = {'gn_rev': '1234'}
deps = {
  'src/buildtools/mac': {'packages': [{'package': 'gn/gn/mac-${{arch}}',
                                       'version': 'git_revision:' + Var('gn_rev')}],
                         'dep_type': 'cipd'},
  'src/third_party/llvm-build/Release+Asserts': {'dep_type': 'gcs', 'bucket': 'b', 'objects': [
      {'object_name': 'Mac/clang-1.tar.xz', 'sha256sum': 'zz', 'size_bytes': 9},
      {'object_name': 'Mac_arm64/clang-1.tar.xz', 'sha256sum': 'aa', 'size_bytes': 5}]},
}
"""
    DAWN = """
vars = {'go': 'version:3@1.0'}
deps = {
  'tools/golang/mac-arm64': {'packages': [{'package': 'infra/3pp/tools/go/mac-arm64', 'version': Var('go')}],
                             'dep_type': 'cipd'},
  'buildtools/mac': {'packages': [{'package': 'gn/gn/mac-${{arch}}', 'version': 'git_revision:1234'}],
                     'dep_type': 'cipd'},
}
"""

    def drift(self, root=ROOT, dawn=DAWN, devtools="deps = {}"):
        source = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, source)
        for name, text in (("DEPS", root), ("third_party/dawn/DEPS", dawn),
                           ("third_party/devtools-frontend/src/DEPS", devtools)):
            (source / name).parent.mkdir(parents=True, exist_ok=True)
            (source / name).write_text(text)
        return toolchains.deps_drift(self.LOCK, source)

    def test_matching_entries_with_vars_resolved(self):
        self.assertEqual(self.drift(), [])

    def test_a_lagging_copy_cannot_mask_a_move_in_the_owning_deps(self):
        # Root DEPS moved gn; dawn's own buildtools/mac entry still names the old revision.
        moved = self.ROOT.replace("'gn_rev': '1234'", "'gn_rev': '5678'")
        self.assertEqual(self.drift(root=moved), ["gn: DEPS no longer pins git_revision:1234"])

    def test_a_moved_object_checksum_is_drift(self):
        moved = self.ROOT.replace("'sha256sum': 'aa'", "'sha256sum': 'bb'")
        self.assertEqual(self.drift(root=moved), ["clang: DEPS no longer pins Mac_arm64/clang-1.tar.xz"])

    def test_a_sub_deps_pin_is_read_from_its_own_file(self):
        moved = self.DAWN.replace("'go': 'version:3@1.0'", "'go': 'version:3@2.0'")
        self.assertEqual(self.drift(dawn=moved), ["go: DEPS no longer pins version:3@1.0"])

    def test_a_destination_nobody_owns_is_drift(self):
        gone = self.DAWN.replace("'tools/golang/mac-arm64'", "'tools/golang/mac-arm64-old'")
        self.assertEqual(self.drift(dawn=gone),
                         ["go: no single DEPS entry owns third_party/dawn/tools/golang/mac-arm64"])

    def test_deps_is_never_executed(self):
        self.assertEqual(self.drift(root=self.ROOT + "\nimport os\nos.system('false')\n"), [])

if __name__ == "__main__":
    unittest.main()
