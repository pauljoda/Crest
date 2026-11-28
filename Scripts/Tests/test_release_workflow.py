#!/usr/bin/env python3
"""Run release preflight against a local Git repository and recorded GitHub data."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
TRIGGERS = REPOSITORY_ROOT / ".github/workflows/release.yml"
WORKFLOW = REPOSITORY_ROOT / ".github/workflows/release-publish.yml"


def workflow_script(step_name: str, workflow: pathlib.Path = WORKFLOW) -> str:
    step = workflow.read_text().split(f"      - name: {step_name}\n", 1)[1]
    match = re.search(r"(?m)^        run: \|\n((?: {10}.*\n|\n)+)", step)
    if match is None:
        raise AssertionError(f"No shell script in {step_name}")
    return textwrap.dedent(match.group(1))


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = pathlib.Path(temporary.name)
        self.repository = self.root / "repository"
        self.repository.mkdir()
        self.git("init", "--initial-branch=main")
        self.git("config", "user.name", "Crest Tests")
        self.git("config", "user.email", "crest-tests@example.invalid")
        self.git("remote", "add", "origin", str(self.repository))
        (self.repository / "Config").mkdir()
        (self.repository / "Config/Version.xcconfig").write_text("MARKETING_VERSION = 0.5.25\n")
        notes = self.repository / "Documentation/ReleaseNotes/0.5/0.5.25.json"
        notes.parent.mkdir(parents=True)
        notes.write_text(
            '{"entries": [{"id": "release-history", "category": "fixed", "message": "Keep release history"}]}\n'
        )
        (self.repository / "Scripts").symlink_to(REPOSITORY_ROOT / "Scripts")
        self.git("add", "Config", "Documentation")
        self.git("commit", "-m", "Previous build")
        self.previous_commit = self.git("rev-parse", "HEAD")
        self.git("tag", "v0.5.24")
        (self.repository / "change.txt").write_text("New change\n")
        self.git("add", "change.txt")
        self.git("commit", "-m", "Current build")
        self.current_commit = self.git("rev-parse", "HEAD")
        self.git("checkout", "-b", "updates")
        (self.repository / "release-note-publication.json").write_text(
            '{"schemaVersion": 1, "channels": {"stable": "release-history", '
            '"development": "release-history", "nightly": "release-history"}}\n'
        )
        self.git("add", "release-note-publication.json")
        self.git("commit", "-m", "Publication cursors")
        self.git("checkout", "main")

        bin_directory = self.root / "bin"
        bin_directory.mkdir()
        self.github_log = self.root / "github.log"
        github = bin_directory / "gh"
        github.write_text(
            "#!/usr/bin/env python3\n"
            "import json, os, sys\n"
            "arguments = sys.argv[1:]\n"
            "with open(os.environ['TEST_GITHUB_LOG'], 'a') as log:\n"
            "    log.write(json.dumps(arguments) + '\\n')\n"
            "responses = json.loads(os.environ.get('TEST_GITHUB_RESPONSES', '{}'))\n"
            "if arguments[0] == 'api' and arguments[-1] in responses:\n"
            "    response = responses[arguments[-1]]\n"
            "    if isinstance(response, dict) and 'calls' in response:\n"
            "        with open(os.environ['TEST_GITHUB_LOG']) as log:\n"
            "            calls = sum(json.loads(line) == arguments for line in log)\n"
            "        response = response['calls'][min(calls, len(response['calls'])) - 1]\n"
            "    if response is None:\n"
            "        sys.exit('GitHub is unreachable')\n"
            "    print(json.dumps(response))\n"
            "    sys.exit(0)\n"
            "if arguments[0] == 'api' and 'releases?per_page=100' in arguments[-1]:\n"
            "    prereleases = [{'tag_name': 'nightly-old', 'draft': False, 'prerelease': True}] * 100\n"
            "    stable = [{'tag_name': 'v0.5.24', 'draft': False, 'prerelease': False}]\n"
            "    print(json.dumps([prereleases, stable] if '--slurp' in arguments else prereleases))\n"
            "    sys.exit(0)\n"
            "sys.exit('Unexpected GitHub request: ' + repr(arguments))\n"
        )
        github.chmod(0o755)
        # Retries wait for nothing here.
        (bin_directory / "sleep").write_text("#!/bin/sh\n")
        (bin_directory / "sleep").chmod(0o755)
        self.environment = os.environ | {
            "PATH": f"{bin_directory}{os.pathsep}{os.environ['PATH']}",
            "GH_TOKEN": "",
            "GITHUB_TOKEN": "",
            "GITHUB_EVENT_NAME": "schedule",
            "GITHUB_REF_TYPE": "branch",
            "GITHUB_REF_NAME": "main",
            "GITHUB_REPOSITORY": "crest-browser/Crest",
            "GITHUB_SHA": self.current_commit,
            "GITHUB_RUN_NUMBER": "61",
            "GITHUB_RUN_ATTEMPT": "1",
            "GITHUB_OUTPUT": str(self.root / "output"),
            "GITHUB_STEP_SUMMARY": str(self.root / "summary"),
            "RUNNER_TEMP": str(self.root),
            "REQUESTED_CHANNEL": "",
            "TEST_GITHUB_LOG": str(self.github_log),
        }

    def git(self, *arguments: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.repository), *arguments],
            check=True, capture_output=True, text=True,
        ).stdout.strip()

    def publish_appcast(
        self, channel: str, commit: str, tag: str, build: int = 1060, version: str | None = None,
    ) -> None:
        self.git("checkout", "updates")
        filename = "appcast-development.xml" if channel == "development" else "appcast.xml"
        short_version = f"<sparkle:shortVersionString>{version}</sparkle:shortVersionString>" if version else ""
        # Stable items carry no channel, and their installers name no commit.
        item_channel = "" if channel == "stable" else f"<sparkle:channel>{channel}</sparkle:channel>"
        installer = (
            f"Installer-Crest-{version}.dmg" if channel == "stable"
            else f"Installer-Crest-0.5.25-{channel}-2026-09-03-{commit[:7]}.dmg"
        )
        (self.repository / filename).write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f"<channel><item>{item_channel}"
            f"<sparkle:version>{build}</sparkle:version>{short_version}"
            f'<enclosure url="https://github.com/crest-browser/Crest/releases/download/{tag}/'
            f'{installer}" />'
            "</item></channel></rss>"
        )
        self.git("add", filename)
        self.git("commit", "-m", "Publish appcast")
        self.git("checkout", "main")

    def preflight(self, **environment: str) -> tuple[subprocess.CompletedProcess[str], dict[str, str]]:
        return self.run_script(workflow_script("Resolve release identity and previous publication"), **environment)

    def run_script(self, script: str, **environment: str) -> tuple[subprocess.CompletedProcess[str], dict[str, str]]:
        output_path = self.root / "output"
        output_path.unlink(missing_ok=True)
        self.github_log.unlink(missing_ok=True)
        result = subprocess.run(
            ["bash", "-c", script],
            cwd=self.repository, env=self.environment | environment,
            capture_output=True, text=True, timeout=20,
        )
        outputs = dict(line.split("=", 1) for line in output_path.read_text().splitlines()) if output_path.exists() else {}
        return result, outputs

    def test_stable_dispatch_and_mismatched_tags_are_rejected(self) -> None:
        scenarios = (
            {"GITHUB_EVENT_NAME": "workflow_dispatch", "REQUESTED_CHANNEL": "stable", "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.5.25"},
            {"GITHUB_EVENT_NAME": "push", "GITHUB_REF_TYPE": "tag", "GITHUB_REF_NAME": "v0.5.24"},
        )
        for environment in scenarios:
            with self.subTest(environment=environment):
                result, outputs = self.preflight(**environment)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(outputs, {})

    def test_the_release_never_runs_for_a_pull_request_event(self) -> None:
        # The release holds the signing secrets, so it runs only for pushes to
        # main and its tags, the schedule, and dispatch, and checks out only
        # the commit its event names. Only a run that publishes joins the
        # queue, so a push that publishes nothing cannot replace one waiting.
        triggers = TRIGGERS.read_text()
        events = re.search(r"(?ms)^on:\n(.*?)^\S", triggers).group(1)
        self.assertEqual(set(re.findall(r"(?m)^  ([a-z_]+):", events)), {"push", "schedule", "workflow_dispatch"})
        push = events.split("  push:\n", 1)[1].split("\n  schedule:", 1)[0]
        self.assertIn("    branches: [main]", push)
        self.assertIn('      - "v*.*.*"', push)
        publish = WORKFLOW.read_text()
        self.assertEqual(re.search(r"(?ms)^on:\n(.*?)^\S", publish).group(1).splitlines()[0], "  workflow_call:")
        for workflow in (triggers, publish):
            self.assertNotIn("allow-unsafe-pr-checkout", workflow)
            self.assertNotRegex(workflow, r"(?m)^concurrency:")
        queued = triggers.split("\n  publish:\n", 1)[1]
        self.assertIn("needs.merge.outputs.pull_request != ''", queued.split("    concurrency:\n", 1)[0])
        self.assertIn("      group: crest-macos-release\n", queued)

    def test_a_push_to_main_publishes_only_a_pull_requests_merge_commit(self) -> None:
        def merged(number: int, merge_commit: str, base: str = "main",
                   merged_at: str = "2026-11-27T22:48:12Z") -> dict[str, object]:
            return {"number": number, "merged_at": merged_at, "base": {"ref": base}, "merge_commit_sha": merge_commit}

        listed = f"repos/crest-browser/Crest/commits/{self.current_commit}/pulls"
        named = "repos/crest-browser/Crest/pulls/1415"
        recent = "repos/crest-browser/Crest/pulls?state=closed&base=main&sort=updated&direction=desc&per_page=100"
        merge = merged(1415, self.current_commit)

        def find(message: str, responses: dict[str, object]) -> tuple[subprocess.CompletedProcess[str], str | None]:
            result, outputs = self.run_script(
                workflow_script("Find the pull request this push merged", TRIGGERS),
                GITHUB_EVENT_NAME="push", HEAD_COMMIT_MESSAGE=message,
                TEST_GITHUB_RESPONSES=json.dumps({recent: [merge, merged(1414, self.previous_commit,
                                                                       merged_at="2026-11-27T22:33:45Z")]}
                                                 | responses),
            )
            return result, outputs.get("pull_request")

        def assert_found(message: str, responses: dict[str, object], expected: str) -> None:
            result, pull_request = find(message, responses)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(pull_request, expected)

        assert_found("Current build", {listed: [merge]}, "1415")
        self.assertIn("the merge commit of #1415", (self.root / "summary").read_text())

        # A direct push, a pull request merged with another commit or into
        # another branch, and one still open publish nothing, without failing.
        for pull_requests in (
            [],
            [merged(1404, self.previous_commit)],
            [merged(1415, self.current_commit, base="release")],
            [merge | {"merged_at": None}],
        ):
            with self.subTest(pull_requests=pull_requests):
                assert_found("Current build", {listed: pull_requests}, "")

        # When GitHub's list lags behind the push, the subject GitHub gives a
        # squash or a merge names the pull request, which must still be merged
        # as this commit. A subject that names none waits for the list.
        for message in ("Walk background tabs (#1415)\n\nKeep the tab beside it (#99)",
                        "Merge pull request #1415 from crest-browser/close-tab\n\nWalk background tabs"):
            with self.subTest(message=message):
                assert_found(message, {listed: [], named: merge}, "1415")
                assert_found(message, {listed: [], named: merged(1415, self.previous_commit)}, "")
                assert_found(message, {listed: None, named: merge}, "1415")
        assert_found("Walk background tabs", {listed: {"calls": [[], [], [merge]]}}, "1415")
        self.assertEqual(self.github_log.read_text().count("/pulls\""), 3)

        # A pull request merged into main after this one has a run that
        # publishes both, so this run stands aside.
        newer = merged(1416, "0" * 40, merged_at="2026-11-27T22:49:02Z")
        assert_found("Current build", {listed: [merge], recent: [newer, merge]}, "")
        self.assertIn("#1416 merged into main after #1415", (self.root / "summary").read_text())

        # When GitHub answers nothing at all, the run fails instead of passing
        # for a direct push.
        result, pull_request = find("Walk background tabs (#1415)", {listed: None, named: None})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not say which pull request", result.stderr)
        self.assertIsNone(pull_request)

        # The publication it starts is Development, from the pushed commit.
        result, outputs = self.preflight(GITHUB_EVENT_NAME="push")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (outputs["channel"], outputs["should_publish"], outputs["source_sha"], outputs["marketing_version"]),
            ("development", "true", self.current_commit, "0.5.26"),
        )

    def test_stable_tag_must_name_the_version_git_gives_its_commit_on_main(self) -> None:
        stable = {"GITHUB_EVENT_NAME": "push", "GITHUB_REF_TYPE": "tag"}
        # The file holds the anchor, 0.5.25; the commit after it is 0.5.26.
        anchor, outputs = self.preflight(**stable, GITHUB_REF_NAME="v0.5.25")
        self.assertNotEqual(anchor.returncode, 0)
        self.assertIn("its tag is v0.5.26", anchor.stderr)
        self.assertEqual(outputs, {})

        result, outputs = self.preflight(**stable, GITHUB_REF_NAME="v0.5.26")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            (outputs["channel"], outputs["marketing_version"], outputs["release_tag"], outputs["previous_commit"]),
            ("stable", "0.5.26", "v0.5.26", self.previous_commit),
        )

        self.git("switch", "-c", "release-candidate")
        (self.repository / "change.txt").write_text("Branch change\n")
        self.git("commit", "-am", "Branch build")
        branch, outputs = self.preflight(**stable, GITHUB_REF_NAME="v0.5.26")
        self.git("switch", "main")
        self.assertNotEqual(branch.returncode, 0)
        self.assertIn("not on main's first-parent history", branch.stderr)
        self.assertEqual(outputs, {})

    def test_a_channel_only_publishes_a_version_newer_than_it_offers(self) -> None:
        # This commit is 0.5.26. Crest refuses an update that isn't newer, so a
        # channel already at or past it from another commit stops the run.
        for published in ("0.5.27", "0.5.26"):
            with self.subTest(published=published):
                self.publish_appcast("nightly", self.previous_commit, "nightly-build", version=published)
                result, outputs = self.preflight()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(f"Crest 0.5.26 is not newer than {published}", result.stderr)
                self.assertEqual(outputs, {})

        # The commit the channel already publishes keeps its version.
        self.publish_appcast("nightly", self.current_commit, "nightly-current", version="0.5.26")
        unchanged, outputs = self.preflight()
        self.assertEqual(unchanged.returncode, 0, unchanged.stderr)
        self.assertEqual(outputs["should_publish"], "false")

        # A Stable installer names no commit, but its tag names its version,
        # which belongs to one commit, so the same Stable release keeps it too.
        self.publish_appcast("stable", self.current_commit, "v0.5.26", version="0.5.26")
        stable, outputs = self.preflight(GITHUB_EVENT_NAME="push", GITHUB_REF_TYPE="tag", GITHUB_REF_NAME="v0.5.26")
        self.assertEqual(stable.returncode, 0, stable.stderr)
        self.assertEqual(outputs["release_tag"], "v0.5.26")

    def test_interrupted_publications_cannot_reuse_another_runs_release_tag(self) -> None:
        self.publish_appcast("nightly", self.previous_commit, "nightly-build", build=1070)
        tags = set()
        for run in ("61", "62"):
            result, outputs = self.preflight(GITHUB_RUN_NUMBER=run)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(outputs["build_number"], "1071")
            tags.add(outputs["release_tag"])
        self.assertEqual(len(tags), 2)


if __name__ == "__main__":
    unittest.main()
