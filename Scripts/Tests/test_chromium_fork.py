"""Protect upstream selection, persistent build ownership, and publication gates."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys
import subprocess
import tarfile
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1] / "control-plane"
sys.path.insert(0, str(SCRIPTS))
import chromium_fork
from chromium_fork import (ADVANCING, ENGINE, Workspace, advance_obstacles, check_build_patches, prepare_update,
                           prune_downloads, prune_sources, rebase_patches, refresh_host_inputs, restore_host_base,
                           select_update, sha256, stable_milestone)
from chromium_artifact import release_ready
from chromium_engine import asset_name, host_patch

spec = importlib.util.spec_from_file_location("publish_chromium_update", SCRIPTS / "publish-chromium-update.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)
spec = importlib.util.spec_from_file_location("resolve_chromium_upstream", SCRIPTS / "resolve-chromium-upstream.py")
resolution = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolution)


def note(title, text):
    return {"title": {"$t": title}, "content": {"$t": f"<p>{text}</p>"}, "published": {"$t": "2026-11-17T11:12:07Z"}}


# Google's notes as they read when 158 was promoted and 159 began early stable.
FEED = {"feed": {"entry": [
    note("Early Stable Update for Desktop", "The Stable channel has been updated to 159.0.8154.13/.14 for Windows, "
         "Mac as part of our early stable release to a small percentage of users."),
    note("Chrome Beta for Desktop Update", "The Beta channel has been updated to 159.0.8154.13 for Windows, Mac and Linux."),
    note("Stable Channel Update for ChromeOS / ChromeOS Flex", "Browser version 158.0.8127.65 for most ChromeOS devices."),
    note("Stable Channel Update for Desktop", "The Chrome team is delighted to announce the promotion of Chrome 158 to "
         "the stable channel. Chrome 158.0.8127.36 (Linux) 158.0.8127.36/.37 (Windows, Mac) contains a number of "
         "fixes. Critical CVE-2026-1000001: Use after free. Fixed in 159.0.8154.2."),
    note("Extended Stable Update for Desktop", "The Extended Stable channel has been updated to 156.0.8078.108/.109."),
]}}


class UpstreamSelectionTests(unittest.TestCase):
    def test_patch_releases_stay_eligible_after_the_next_milestone_ships(self):
        releases = ["157.0.8103.26", "156.0.8078.80", "156.0.8078.47", "unrecognized"]
        result = select_update("156.0.8078.47", releases, stable_milestone=157)
        self.assertEqual(result["candidate"], "156.0.8078.80")
        self.assertEqual(result["latest"], "157.0.8103.26")
        self.assertTrue(result["majorReviewRequired"])
        self.assertEqual(select_update("156.0.8078.47", releases, True, 157)["candidate"], "157.0.8103.26")

    def test_only_a_full_stable_desktop_note_promotes_a_milestone(self):
        self.assertEqual(stable_milestone(FEED), 158)
        self.assertIsNone(stable_milestone(None))
        # chromiumdash lists 159's early stable build among stable releases.
        releases = ["159.0.8154.13", "157.0.8103.81", "158.0.8127.37", "158.0.8127.36", "157.0.8103.80"]
        result = select_update("157.0.8103.80", releases, True, stable_milestone(FEED))
        self.assertEqual((result["candidate"], result["earlyStable"]), ("158.0.8127.37", "159.0.8154.13"))
        # A respin without a note of its own stays a fix on the pinned milestone.
        self.assertEqual(select_update("157.0.8103.80", releases, False, 158)["candidate"], "157.0.8103.81")
        # Without the notes, nothing past the pinned milestone is trusted to be full stable.
        unchecked = select_update("157.0.8103.80", releases, True, None)
        self.assertEqual((unchecked["candidate"], unchecked["earlyStable"]), ("157.0.8103.81", None))

    def test_a_schedule_takes_a_full_stable_milestone_and_checks_early_stable_once(self):
        releases = ["159.0.8154.13", "158.0.8127.37", "157.0.8103.81"]
        inputs = dict(event="schedule", operation="check", requested="", allow_major=False, upstream_enabled=True,
                      build_enabled=True, current="157.0.8103.81", releases=releases, feed=FEED, reviews=[])
        with mock.patch.object(resolution, "release_notes", return_value={"exploited": False}):
            outputs, _, _ = resolution.resolve(**inputs)
            self.assertEqual((outputs["operation"], outputs["version"], outputs["major"], outputs["preflight"]),
                             ("update", "158.0.8127.37", "true", "159.0.8154.13"))
            checked = [{"headRefName": "codex/chromium-preflight-159.0.8154.13-abc", "state": "CLOSED", "url": "u"},
                       {"headRefName": "chromium-158", "state": "OPEN", "url": "v",
                        "title": "Update Chromium to 158.0.8127.37"}]
            outputs, _, _ = resolution.resolve(**inputs | {"reviews": checked})
            self.assertEqual((outputs["operation"], outputs["preflight"]), ("check", ""))
            outputs, _, _ = resolution.resolve(**inputs | {"current": "158.0.8127.37"})
            self.assertEqual((outputs["operation"], outputs["preflight"]), ("check", "159.0.8154.13"))

    def test_updates_advance_but_downgrades_and_equal_versions_do_not(self):
        releases = ["156.0.8078.80", "156.0.8078.79"]
        self.assertEqual(select_update("156.0.8078.79", releases)["candidate"], "156.0.8078.80")
        self.assertIsNone(select_update("156.0.8078.80", releases)["candidate"])


class WorkspaceTests(unittest.TestCase):
    def host(self, root, patches):
        repo = root / "repo"
        host = repo / "CrestEngines/Chromium"
        (host / "Patches").mkdir(parents=True)
        for name, text in patches.items():
            (host / "Patches" / name).write_text(text)
        (host / "Patches/series").write_text("# order\n" + "".join(f"{name}\n" for name in patches))
        return repo, host

    def test_host_refresh_requires_every_patch_hunk_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "src"
            patch = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail\n"
            repo, host = self.host(root, {"native-host.patch": patch})
            source.mkdir()
            original = "context\nold\ntail\n"
            (source / "sample.cc").write_text(original)
            refresh_host_inputs(repo, source)
            pinned = (host / "host-inputs.json").read_text()
            hashes = json.loads(pinned)["sample.cc"]
            self.assertNotEqual(hashes["before"], hashes["after"])
            self.assertEqual((source / "sample.cc").read_text(), original)
            installed = root / "host.json"
            installed.write_text(json.dumps({"patch": patch, "inputs": json.loads(pinned)}))
            (source / "sample.cc").write_text("context\nnew\ntail\n")
            refresh_host_inputs(repo, source, installed)
            self.assertEqual((host / "host-inputs.json").read_text(), pinned)
            self.assertEqual((source / "sample.cc").read_text(), "context\nnew\ntail\n")
            (source / "sample.cc").write_text("changed context\nold\ntail\n")
            with self.assertRaises(subprocess.CalledProcessError):
                refresh_host_inputs(repo, source)
            self.assertEqual((host / "host-inputs.json").read_text(), pinned)

    def test_a_file_two_patches_change_takes_them_in_order_and_restores_in_reverse(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "src"
            first = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n"
            second = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,4 +1,4 @@\n a\n B\n-c\n+C\n d\n"
            repo, host = self.host(root, {"native-host.patch": first, "privacy.patch": second})
            source.mkdir()
            (source / "sample.cc").write_text("a\nb\nc\nd\n")
            refresh_host_inputs(repo, source)
            hashes = json.loads((host / "host-inputs.json").read_text())["sample.cc"]
            combined = host_patch(repo)
            subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-s"], input=combined, text=True, cwd=source, check=True)
            self.assertEqual((source / "sample.cc").read_text(), "a\nB\nC\nd\n")
            self.assertEqual(hashlib.sha256((source / "sample.cc").read_bytes()).hexdigest(), hashes["after"])
            restore_host_base(source, {"patch": combined, "inputs": {"sample.cc": hashes}}, {})
            self.assertEqual((source / "sample.cc").read_text(), "a\nb\nc\nd\n")
            (host / "Patches/privacy.patch").write_text(second + second)
            with self.assertRaises(ValueError):
                host_patch(repo)


class UpdatePlanTests(unittest.TestCase):
    def test_only_a_same_toolchain_fix_advances_the_built_tree(self):
        tool = {"package": "infra/tools/go", "version": "1", "sha256": "a" * 64}
        lock = {"chromium": {"version": "157.0.8103.51"}, "dependencies": ["src/third_party/llvm-build"],
                "cipd": {"src/go": tool}}
        clang = {"src/third_party/llvm-build": ("bucket", [{"object_name": "clang-1.tar.xz", "sha256sum": "1"}])}
        fix = {**lock, "chromium": {"version": "157.0.8103.80"}}
        self.assertEqual(advance_obstacles(lock, fix, clang, clang), [])
        newer_clang = {"src/third_party/llvm-build": ("bucket", [{"object_name": "clang-2.tar.xz", "sha256sum": "2"}])}
        self.assertEqual(len(advance_obstacles(lock, fix, clang, newer_clang)), 1)
        self.assertEqual(len(advance_obstacles(lock, fix | {"cipd": {"src/go": tool | {"version": "2"}}}, clang, clang)), 1)
        self.assertEqual(len(advance_obstacles(lock, {**lock, "chromium": {"version": "158.0.8127.37"}}, clang, clang)), 1)

    def test_patches_carry_over_by_applying_merging_or_reporting_conflicts(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            host = root / "repo/CrestEngines/Chromium/Patches"
            host.mkdir(parents=True)
            names = ("same.cc", "moved.cc", "merged.cc", "clash.cc", "gone.cc", "ready.cc", "landed.cc")
            pinned = {name: "a\nb\nc\nd\ne\nf\ng\nh\n" for name in names}
            # A patch already rebased for the release no longer matches the pinned file.
            pinned["ready.cc"] = "a\nb\nold\nd\ne\nf\ng\nh\n"
            patch = "".join(f"--- a/{name}\n+++ b/{name}\n@@ -2,7 +2,7 @@\n b\n c\n d\n-e\n+E\n f\n g\n h\n"
                            for name in names)
            (host / "native-host.patch").write_text("Why Crest changes these files.\n" + patch)
            (host / "series").write_text("native-host.patch\n")
            release = {"same.cc": pinned["same.cc"], "moved.cc": "new\n" + pinned["moved.cc"],
                       "merged.cc": "a\nB\nc\nd\ne\nf\ng\nh\n", "clash.cc": "a\nb\nc\nd\nX\nf\ng\nh\n",
                       "gone.cc": None, "ready.cc": pinned["same.cc"],
                       # The release already has Crest's change: the patch must not pass by applying in reverse.
                       "landed.cc": "a\nb\nc\nd\nE\nf\ng\nh\n"}
            report = root / "report"
            statuses = rebase_patches(root / "repo", pinned, release, report)["native-host.patch"]
            self.assertEqual(statuses, {"same.cc": "unchanged", "moved.cc": "applies", "merged.cc": "rebased",
                                        "clash.cc": "conflict", "gone.cc": "missing", "ready.cc": "applies",
                                        "landed.cc": "upstream"})
            rebased = (report / "Patches/native-host.patch").read_text()
            self.assertTrue(rebased.startswith("Why Crest changes these files.\n"))
            source = root / "source"
            source.mkdir()
            (source / "merged.cc").write_text(release["merged.cc"])
            section = rebased[rebased.index("--- a/merged.cc"):rebased.index("--- a/clash.cc")]
            subprocess.run(["patch", "--batch", "--fuzz=0", "-p1", "-s"], input=section, text=True, cwd=source, check=True)
            self.assertEqual((source / "merged.cc").read_text(), "a\nB\nc\nd\nE\nf\ng\nh\n")
            self.assertIn("<<<<<<<", (report / "conflicts/native-host.patch/clash.cc").read_text())
            self.assertNotIn("landed.cc", rebased)

    def test_advancing_rewrites_only_what_the_release_changed(self):
        # Preparation extracts files with their archive mode; match it for every file written here.
        self.addCleanup(os.umask, os.umask(0o022))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, workspace = root / "repo", root / "workspace"
            (repo / "CrestEngines/Chromium").mkdir(parents=True)
            (repo / "Scripts/control-plane").mkdir(parents=True)
            (repo / "Scripts/control-plane/prepare-chromium.py").write_text("# preparation\n")
            downloads = workspace / "downloads"
            downloads.mkdir(parents=True)

            def archive(version, files, links=None, executables=()):
                path = downloads / f"chromium-{version}-lite.tar.xz"
                staging = root / f"staging-{version}"
                for name, text in files.items():
                    if text is None:
                        continue
                    (staging / f"chromium-{version}" / name).parent.mkdir(parents=True, exist_ok=True)
                    (staging / f"chromium-{version}" / name).write_text(text)
                for name, target in (links or {}).items():
                    (staging / f"chromium-{version}" / name).symlink_to(target)
                for name in executables:
                    (staging / f"chromium-{version}" / name).chmod(0o755)
                with tarfile.open(path, "w:xz") as stream:
                    stream.add(staging / f"chromium-{version}", f"chromium-{version}")
                return path

            def pin(version, path):
                lock = {"chromium": {"version": version, "sourceArchive": f"https://example.invalid/{path.name}",
                                     "sourceArchiveSha256": sha256(path)},
                        "dependencies": ["src/third_party/tool"], "cipd": {}, "crestPatches": {}}
                (repo / "CrestEngines/Chromium/source.lock.json").write_text(json.dumps(lock))
                return Workspace(workspace, repo)

            original = {"same.cc": "same\n", "changed.cc": "old\n", "dropped.cc": "dropped\n",
                        "docs/old/notes.md": "notes\n", "docs/old/more.md": "more\n",
                        "turned": "a file\n", "was_dir/inner.cc": "inner\n", "legacy/api.h": "api\n",
                        "tool.sh": "#!/bin/sh\n",
                        "patched.cc": "context\nold\n", "third_party/tool/linux": "linux build\n"}
            previous = archive("157.0.8103.51", original)
            release = archive("157.0.8103.80", {**original, "changed.cc": "new\n", "added.cc": "added\n",
                                                "third_party/tool/linux": "newer linux build\n"}
                              | {"dropped.cc": None, "docs/old/notes.md": None, "docs/old/more.md": None,
                                 # A file that becomes a directory, and a directory that becomes a file.
                                 "turned": None, "turned/child.cc": "child\n",
                                 "was_dir/inner.cc": None, "was_dir": "a file now\n",
                                 # A directory moved and replaced by a link to its new place.
                                 "legacy/api.h": None, "include/api.h": "api\n"},
                              links={"legacy": "include"}, executables=("tool.sh",))
            pinned = pin("157.0.8103.51", previous)
            source = pinned.source
            source.mkdir(parents=True)
            for name, text in original.items():
                (source / name).parent.mkdir(parents=True, exist_ok=True)
                (source / name).write_text(text)
            (source / "third_party/tool/linux").write_text("mac toolchain\n")
            (source / "out/CrestBaseline").mkdir(parents=True)
            (source / "out/CrestBaseline/obj.o").write_text("object\n")
            host = "--- a/patched.cc\n+++ b/patched.cc\n@@ -1,2 +1,2 @@\n context\n-old\n+crest\n"
            (source / "patched.cc").write_text("context\ncrest\n")
            (pinned.directory / "host.json").write_text(json.dumps({"patch": host, "inputs": {"patched.cc": {
                "before": sha256(root / "staging-157.0.8103.51/chromium-157.0.8103.51/patched.cc"),
                "after": sha256(source / "patched.cc")}}}))
            os.utime(source / "same.cc", (1, 1))
            target = pin("157.0.8103.80", release)
            self.assertEqual(pinned.advance(target, previous), {"changed": 9, "removed": 3})
            advanced = target.source
            self.assertFalse(pinned.directory.exists())
            self.assertFalse((target.directory / ADVANCING).exists())
            self.assertEqual(json.loads((target.directory / "prepared.json").read_text())["preparationKey"], target.key)
            self.assertEqual((advanced / "changed.cc").read_text(), "new\n")
            self.assertEqual((advanced / "added.cc").read_text(), "added\n")
            self.assertFalse((advanced / "dropped.cc").exists())
            self.assertFalse((advanced / "docs").exists())
            self.assertEqual((advanced / "turned/child.cc").read_text(), "child\n")
            self.assertEqual((advanced / "was_dir").read_text(), "a file now\n")
            self.assertEqual((advanced / "include/api.h").read_text(), "api\n")
            self.assertEqual(os.readlink(advanced / "legacy"), "include")
            self.assertEqual(stat.S_IMODE((advanced / "tool.sh").stat().st_mode), 0o755)
            self.assertEqual((advanced / "patched.cc").read_text(), "context\nold\n")
            self.assertEqual((advanced / "same.cc").stat().st_mtime, 1)
            self.assertEqual((advanced / "third_party/tool/linux").read_text(), "mac toolchain\n")
            self.assertEqual((advanced / "out/CrestBaseline/obj.o").read_text(), "object\n")
            self.assertFalse((target.directory / "host.json").exists())

    def test_build_patches_must_fit_the_release_before_its_source_is_touched(self):
        with tempfile.TemporaryDirectory() as temporary:
            repo = Path(temporary) / "repo"
            (repo / ENGINE / "Patches").mkdir(parents=True)
            (repo / ENGINE / "Patches/unwind.patch").write_text(
                "--- a/chrome/BUILD.gn\n+++ b/chrome/BUILD.gn\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n")
            lock = {"crestPatches": {"Patches/unwind.patch": "digest"}}
            self.assertEqual(check_build_patches(repo, lock, {"chrome/BUILD.gn": b"a\nb\nc\n"}),
                             {"Patches/unwind.patch": "applies"})
            for release in ({"chrome/BUILD.gn": b"a\nchanged\nc\n"}, {"chrome/BUILD.gn": b"a\nB\nc\n"},
                            {"chrome/BUILD.gn": None}):
                with self.subTest(release=release):
                    self.assertEqual(check_build_patches(repo, lock, release), {"Patches/unwind.patch": "fails"})

    def test_only_a_built_tree_advances_and_a_stopped_advance_stops_the_update(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, workspace = root / "repo", root / "workspace"
            (repo / ENGINE).mkdir(parents=True)
            (repo / "Scripts/control-plane").mkdir(parents=True)
            (repo / "Scripts/control-plane/prepare-chromium.py").write_text("# preparation\n")
            lock = {"chromium": {"version": "157.0.8103.51"}, "dependencies": [], "cipd": {}, "crestPatches": {}}
            candidate = lock | {"chromium": {"version": "157.0.8103.80"}}
            (repo / ENGINE / "source.lock.json").write_text(json.dumps(lock))
            (repo / ENGINE / "host-inputs.json").write_text("{}")
            pinned = Workspace(workspace, repo)
            pinned.directory.mkdir(parents=True)
            (pinned.directory / "prepared.json").write_text("{}")
            plan = {"path": "advance", "blocked": False, "report": "report"}
            with (mock.patch.object(chromium_fork, "plan_update", return_value=(plan, candidate)),
                  mock.patch.object(Workspace, "advance") as advance, mock.patch.object(Workspace, "prepare") as prepare,
                  mock.patch.object(chromium_fork, "refresh_host_inputs"),
                  mock.patch.object(chromium_fork, "prune_sources", return_value=[]),
                  mock.patch("builtins.print")):
                prepare_update(repo, workspace, "157.0.8103.80")
            # No installed host to reverse: the update prepares a fresh source instead.
            advance.assert_not_called()
            prepare.assert_called_once()
            (repo / ENGINE / "source.lock.json").write_text(json.dumps(lock))
            (pinned.directory / ADVANCING).write_text("{}")
            with (mock.patch.object(chromium_fork, "plan_update", return_value=(plan, candidate)),
                  mock.patch("builtins.print"), self.assertRaises(ValueError)):
                prepare_update(repo, workspace, "157.0.8103.80")
            self.assertEqual(json.loads((repo / ENGINE / "source.lock.json").read_text()), lock)

    def test_every_overlay_source_must_be_compiled_into_the_browser(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            overlay = root / "repo" / ENGINE / "Overlay/chrome/browser/ui/crest"
            overlay.mkdir(parents=True)
            (overlay / "crest_window.mm").write_text("")
            (overlay / "crest_window.h").write_text("")
            (root / "src/out/CrestBaseline").mkdir(parents=True)
            # A stand-in for Ninja's inputs tool: what the browser target compiles.
            ninja = root / "ninja"
            ninja.write_text("#!/bin/sh\nprintf '../../chrome/browser/ui/crest/crest_window.mm\\n../../base/base.cc\\n'\n")
            ninja.chmod(0o755)
            chromium_fork.require_overlay_compiled(root / "repo", root / "src", ninja)
            # A source whose object only some other target makes is not in the browser.
            (overlay / "crest_elsewhere.cc").write_text("")
            with self.assertRaises(ValueError):
                chromium_fork.require_overlay_compiled(root / "repo", root / "src", ninja)

    def test_a_milestone_replaces_the_pinned_source_only_once_its_engine_is_published(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            pinned_directory, release_directory = root / "sources" / ("a" * 20), root / "sources" / ("b" * 20)
            pinned_directory.mkdir(parents=True)
            pinned = mock.Mock(directory=pinned_directory)
            release = mock.Mock(directory=release_directory, lock={"chromium": {"version": "158.0.8127.37"}})
            full = mock.Mock(free=20 * 1024**3)
            with mock.patch.object(chromium_fork.shutil, "disk_usage", return_value=full), \
                    mock.patch.object(chromium_fork, "building", return_value=False), \
                    mock.patch.object(chromium_fork.chromium_artifact, "published_release", return_value=None):
                with self.assertRaisesRegex(ValueError, "needs 50 GiB free and 20 GiB is free"):
                    chromium_fork.make_room_for_milestone(root, pinned, release, "k" * 64, "owner/repo")
                self.assertTrue(pinned_directory.is_dir())
            with mock.patch.object(chromium_fork.shutil, "disk_usage", return_value=full), \
                    mock.patch.object(chromium_fork, "building", return_value=False), \
                    mock.patch.object(chromium_fork.chromium_artifact, "release_ready", return_value=True), \
                    mock.patch.object(chromium_fork.chromium_artifact, "published_release", return_value={}):
                self.assertEqual(chromium_fork.make_room_for_milestone(root, pinned, release, "k" * 64, "owner/repo"),
                                 ["a" * 20])
            self.assertFalse(pinned_directory.exists())

    def test_pruning_waits_for_a_running_build(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "sources" / ("a" * 20)).mkdir(parents=True)
            (root / "sources" / ("b" * 20)).mkdir()
            (root / "profiles").mkdir()
            (root / "profiles/old.profdata").write_text("")
            (root / "profiles/new-x64.profdata").write_text("")
            lock = {"chromium": {"sourceArchive": "https://example.invalid/new.tar.xz"},
                    "architectures": {"arm64": {"pgoProfile": "new.profdata"},
                                      "x64": {"pgoProfile": "new-x64.profdata"}}}
            with mock.patch.object(chromium_fork, "building", return_value=True):
                with self.assertRaises(ValueError):
                    prune_sources(root, {"a" * 20})
                with self.assertRaises(ValueError):
                    prune_downloads(root, lock)
            self.assertTrue((root / "sources" / ("b" * 20)).exists())
            self.assertTrue((root / "profiles/old.profdata").exists())
            with mock.patch.object(chromium_fork, "building", return_value=False):
                self.assertEqual(prune_sources(root, {"a" * 20}), ["b" * 20])
                self.assertEqual(prune_downloads(root, lock), ["old.profdata"])
            self.assertTrue((root / "profiles/new-x64.profdata").exists())


class PublicationTests(unittest.TestCase):
    def test_a_draft_takes_only_its_own_update_receipt(self):
        with tempfile.TemporaryDirectory() as temporary:
            report = Path(temporary)
            (report / "plan.json").write_text(json.dumps({"version": "157.0.8103.80"}))
            receipt = {"chromium": "157.0.8103.80", "commit": "c" * 40, "engineKey": "k" * 64, "plan": str(report)}
            expected = dict(version="157.0.8103.80", base_sha="c" * 40, engine_key="k" * 64)
            self.assertEqual(publication.update_plan(receipt, **expected)["version"], "157.0.8103.80")
            for other in ({name: value for name, value in receipt.items() if name != "plan"},
                          receipt | {"chromium": "157.0.8103.79"}, receipt | {"commit": "d" * 40},
                          receipt | {"engineKey": "j" * 64}):
                with self.subTest(receipt=other), self.assertRaises(ValueError):
                    publication.update_plan(other, **expected)

    def test_engine_must_be_complete_and_match_the_full_key(self):
        key = "a" * 64
        asset = asset_name(key)
        release = {"draft": False, "body": f"Engine key `{key}`", "assets": [
            {"name": name, "size": 100, "state": "uploaded"} for name in (asset, f"{asset}.sha256")]}
        self.assertTrue(release_ready(release, key))
        self.assertFalse(release_ready(None, key))
        self.assertFalse(release_ready(release | {"draft": True}, key))
        for incomplete in (release | {"assets": release["assets"][:1]},
                           release | {"body": "a" * 16 + "b" * 48},
                           release | {"assets": [item | {"state": "new"} for item in release["assets"]]},
                           release | {"assets": [item | {"size": 0} for item in release["assets"]]}):
            with self.subTest(release=incomplete), self.assertRaises(ValueError):
                release_ready(incomplete, key)


if __name__ == "__main__":
    unittest.main()
