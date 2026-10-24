"""Protect upstream selection, persistent build ownership, and publication gates."""
import datetime
import importlib.util
import json
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1] / "control-plane"
sys.path.insert(0, str(SCRIPTS))
from chromium_fork import (certificate_trust, exclusive_workspace, prune_sources, refresh_host_inputs,
                           renewal_issue_change, restore_host_base, select_update, sha256, validate_workspace)
from chromium_artifact import release_ready
from chromium_engine import asset_name

spec = importlib.util.spec_from_file_location("publish_chromium_update", SCRIPTS / "publish-chromium-update.py")
publication = importlib.util.module_from_spec(spec)
spec.loader.exec_module(publication)


class UpstreamSelectionTests(unittest.TestCase):
    def test_patch_releases_stay_eligible_after_the_next_milestone_ships(self):
        releases = [{"tag_name": tag} for tag in ("154.0.8000.10-1.1", "152.0.7977.90-1.1", "152.0.7977.82-1.1")]
        releases += [{"tag_name": "152.0.7977.99-1.1", "draft": True},
                     {"tag_name": "152.0.7977.98-1.1", "prerelease": True},
                     {"tag_name": "unrecognized-tag"}]
        result = select_update("152.0.7977.82-1.1", releases)
        self.assertEqual(result["candidate"], "152.0.7977.90-1.1")
        self.assertEqual(result["latest"], "154.0.8000.10-1.1")
        self.assertTrue(result["majorReviewRequired"])
        self.assertEqual(select_update("152.0.7977.82-1.1", releases, True)["candidate"], "154.0.8000.10-1.1")

    def test_revision_updates_advance_but_downgrades_and_equal_versions_do_not(self):
        releases = [{"tag_name": tag} for tag in ("152.0.7977.82-1.2", "152.0.7977.81-1.1")]
        self.assertEqual(select_update("152.0.7977.82-1.1", releases)["candidate"], "152.0.7977.82-1.2")
        self.assertIsNone(select_update("152.0.7977.82-1.2", releases)["candidate"])


class CertificateTrustTests(unittest.TestCase):
    def test_renewal_is_due_two_weeks_before_transparency_stops_being_enforced(self):
        files = {
            ("refs/tags/155.0.8059.84", "components/certificate_transparency/data/log_list.json"):
                '{"log_list_timestamp": "2026-09-20T13:35:40Z"}',
            ("refs/tags/155.0.8059.84", "net/data/ssl/chrome_root_store/root_store.textproto"): "version_major: 39\n",
            ("main", "net/data/ssl/chrome_root_store/root_store.textproto"): "version_major: 43\n",
        }
        read = lambda ref, path: files[ref, path]
        early = certificate_trust("155.0.8059.84",
                                  datetime.datetime(2026, 11, 15, 13, 35, 39, tzinfo=datetime.UTC), read)
        self.assertFalse(early["renewalDue"])
        self.assertEqual((early["rootStoreVersion"], early["upstreamRootStoreVersion"]), (39, 43))
        due = certificate_trust("155.0.8059.84",
                                datetime.datetime(2026, 11, 15, 13, 35, 40, tzinfo=datetime.UTC), read)
        self.assertTrue(due["renewalDue"])
        self.assertEqual(due["transparencyEnforcedUntil"], "2026-11-29T13:35:40+00:00")

    def test_one_renewal_issue_opens_while_due_and_closes_once_renewed(self):
        due = {"chromium": "155.0.8059.84", "transparencyEnforcedUntil": "2026-11-29T13:35:40+00:00",
               "daysLeft": 14, "renewalDue": True}
        self.assertEqual(renewal_issue_change(due, [])[0], "create")
        self.assertIsNone(renewal_issue_change(due, [42]))
        renewed = dict(due, chromium="156.0.8078.48", daysLeft=60, renewalDue=False)
        self.assertEqual(renewal_issue_change(renewed, [42])[:2], ("close", ("42", "--comment",
            "Chromium 156.0.8078.48 enforces Certificate Transparency until 2026-11-29.")))
        self.assertIsNone(renewal_issue_change(renewed, []))


class WorkspaceTests(unittest.TestCase):
    def test_switching_host_revisions_accepts_an_exact_legacy_install_but_preserves_local_edits(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary)
            path = source / "sample.cc"
            hashes = {}
            for state in ("base", "old", "desired"):
                path.write_text(f"{state}\n")
                hashes[state] = sha256(path)
            previous = {"patch": "--- a/sample.cc\n+++ b/sample.cc\n@@ -1 +1 @@\n-base\n+old\n",
                        "inputs": {"sample.cc": {"before": hashes["base"], "after": hashes["old"]}}}
            desired = {"sample.cc": {"before": hashes["base"], "after": hashes["desired"]}}
            restore_host_base(source, previous, desired)
            self.assertEqual(path.read_text(), "desired\n")
            path.write_text("old\n")
            restore_host_base(source, previous, desired)
            self.assertEqual(path.read_text(), "base\n")
            path.write_text("unreviewed local edit\n")
            with self.assertRaisesRegex(ValueError, "Locally modified"):
                restore_host_base(source, previous, desired)
            self.assertEqual(path.read_text(), "unreviewed local edit\n")

    def test_independent_operations_cannot_share_a_locked_workspace(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with exclusive_workspace(root):
                with self.assertRaisesRegex(ValueError, "Another Chromium operation"):
                    with exclusive_workspace(root):
                        self.fail("Second writer obtained the lock")
            with exclusive_workspace(root):
                pass

    def test_workspace_cannot_alias_or_contain_the_product_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo = root / "Crest"
            repo.mkdir()
            alias = root / "alias"
            alias.symlink_to(repo, target_is_directory=True)
            for workspace in (root, repo, repo / "build", alias / "build"):
                with self.subTest(workspace=workspace), self.assertRaises(ValueError):
                    validate_workspace(workspace, repo)
            self.assertEqual(validate_workspace(root / "CrestChromium", repo), (root / "CrestChromium").resolve())

    def test_the_workspace_runner_may_check_crest_out_in_its_own_work_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            workspace = Path(temporary) / "CrestChromium"
            checkout = workspace / "runner-work" / "Crest" / "Crest"
            checkout.mkdir(parents=True)
            self.assertEqual(validate_workspace(workspace, checkout), workspace.resolve())
            elsewhere = workspace / "sources" / "Crest"
            elsewhere.mkdir(parents=True)
            with self.assertRaises(ValueError):
                validate_workspace(workspace, elsewhere)

    def test_pruning_removes_only_other_prepared_sources(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.assertEqual(prune_sources(root, set()), [])
            sources = root / "sources"
            pinned, update, superseded = "a" * 20, "b" * 20, "c" * 20
            for name in (pinned, update, superseded, "manual-build"):
                (sources / name / "upstream").mkdir(parents=True)
            (sources / ("d" * 20)).symlink_to(sources / pinned)
            self.assertEqual(prune_sources(root, {pinned, update}), [superseded])
            self.assertEqual(sorted(path.name for path in sources.iterdir()),
                             [pinned, update, "d" * 20, "manual-build"])
            self.assertTrue((sources / pinned / "upstream").is_dir())

    def test_host_refresh_requires_every_patch_hunk_and_preserves_source(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            repo, source = root / "repo", root / "src"
            host = repo / "CrestEngines/Chromium"
            (host / "Patches").mkdir(parents=True)
            source.mkdir()
            patch = "--- a/sample.cc\n+++ b/sample.cc\n@@ -1,3 +1,3 @@\n context\n-old\n+new\n tail\n"
            (host / "Patches/native-host.patch").write_text(patch)
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


class PromotionTests(unittest.TestCase):
    def test_automatic_publication_requires_opt_in_and_development_on_main(self):
        policy = {"automaticChannel": "development", "integrationBranch": "main", "automaticMajorUpdates": False}
        arguments = dict(enabled="true", default_branch="main", major_update=False)
        self.assertTrue(publication.automatic_release_allowed(policy, **arguments))
        for name, value in (("enabled", "false"), ("enabled", None),
                            ("default_branch", "chromium-control-plane"), ("major_update", True)):
            with self.subTest(gate=name):
                self.assertFalse(publication.automatic_release_allowed(policy, **(arguments | {name: value})))
        for channel in ("stable", "experimental", "nightly"):
            with self.subTest(channel=channel):
                self.assertFalse(publication.automatic_release_allowed(policy | {"automaticChannel": channel}, **arguments))

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


class ReleaseNoteTests(unittest.TestCase):
    def test_update_note_is_appended_last_without_rewriting_existing_entries(self):
        catalog = ('{\n  "schemaVersion": 2,\n  "entries": {\n    "earlier": {\n      "category": "fixed",\n'
                   '      "message": "Downloads follow the site you\u2019re on. Settings \\u203a About."\n    }\n  }\n}\n')
        note = {"category": "fixed", "message": "Chromium is updated to 154.0.8037.97 with upstream fixes."}
        appended = publication.append_release_note(catalog, "chromium-upstream-154", note)
        self.assertTrue(appended.startswith(catalog[:-len("\n    }\n  }\n}\n")] + "\n    },\n"))
        self.assertEqual(list(json.loads(appended)["entries"].items())[-1], ("chromium-upstream-154", note))
        with self.assertRaises(ValueError):
            publication.append_release_note(appended, "chromium-upstream-154", note)


if __name__ == "__main__":
    unittest.main()
