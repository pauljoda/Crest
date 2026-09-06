#!/usr/bin/env python3
"""Regression coverage for the generated public roadmap section."""

from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPOSITORY_ROOT / "Scripts" / "render-roadmap.py"


def load_renderer():
    spec = importlib.util.spec_from_file_location("crest_roadmap_renderer", SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load Scripts/render-roadmap.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class RenderRoadmapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.renderer = load_renderer()

    def test_release_order_status_and_commit_evidence(self) -> None:
        snapshot = {
            "milestones": [
                {"number": 3, "title": "0.6", "state": "open"},
                {"number": 1, "title": "0.5", "state": "open"},
                {"number": 4, "title": "0.4", "state": "closed"},
            ],
            "issues": [
                {
                    "number": 20,
                    "title": "Later work",
                    "url": "https://github.com/pauljoda/Crest/issues/20",
                    "state": "OPEN",
                    "labels": [{"name": "roadmap"}],
                    "milestone": {"title": "0.6"},
                    "body": "<!-- crest-linear-sync\nissue: APP-300\n-->",
                },
                {
                    "number": 12,
                    "title": "Delivered work",
                    "url": "https://github.com/pauljoda/Crest/issues/12",
                    "state": "CLOSED",
                    "labels": [{"name": "roadmap"}],
                    "milestone": {"title": "0.5"},
                    "body": "<!-- crest-linear-sync\nissue: APP-250\ncommit: abcdef1234567890\n-->",
                },
                {
                    "number": 11,
                    "title": "Current work",
                    "url": "https://github.com/pauljoda/Crest/issues/11",
                    "state": "OPEN",
                    "labels": [{"name": "roadmap"}],
                    "milestone": {"title": "0.5"},
                    "body": "",
                },
            ],
        }

        rendered = self.renderer.render_managed_section(snapshot, "pauljoda/Crest")

        self.assertLess(rendered.index("### [0.5]"), rendered.index("### [0.6]"))
        self.assertIn("- [ ] [Current work]", rendered)
        self.assertIn("- [x] [Delivered work]", rendered)
        self.assertIn("/commit/abcdef1234567890", rendered)
        self.assertNotIn("### [0.4]", rendered)

    def test_replacement_preserves_manually_maintained_sections(self) -> None:
        document = """# Roadmap

Intro.

<!-- crest-roadmap-sync:start -->
old generated content
<!-- crest-roadmap-sync:end -->

## Release gates

- Keep this text.
"""
        managed = """<!-- crest-roadmap-sync:start -->
new generated content
<!-- crest-roadmap-sync:end -->"""

        rendered = self.renderer.replace_managed_section(document, managed)

        self.assertIn("new generated content", rendered)
        self.assertNotIn("old generated content", rendered)
        self.assertIn("## Release gates\n\n- Keep this text.", rendered)

    def test_canceled_work_is_not_presented_as_delivered(self) -> None:
        snapshot = {
            "milestones": [{"number": 2, "title": "0.6", "state": "open"}],
            "issues": [
                {
                    "number": number,
                    "title": title,
                    "url": f"https://github.com/pauljoda/Crest/issues/{number}",
                    "state": state,
                    "stateReason": reason,
                    "labels": ["roadmap"],
                    "milestone": {"title": "0.6"},
                    "body": "",
                }
                for number, title, state, reason in [
                    (1, "Shipped fix", "CLOSED", "COMPLETED"),
                    (2, "Withdrawn proposal", "CLOSED", "NOT_PLANNED"),
                    (3, "Reopened proposal", "OPEN", "REOPENED"),
                ]
            ],
        }

        rendered = self.renderer.render_managed_section(snapshot, "pauljoda/Crest")

        planned, rest = rendered.split("#### Completed", 1)
        completed, withdrawn = rest.split("#### Not planned", 1)
        self.assertIn("Reopened proposal", planned)
        self.assertIn("Shipped fix", completed)
        self.assertNotIn("Withdrawn proposal", completed)
        self.assertIn("Withdrawn proposal", withdrawn)
        self.assertNotIn("Shipped fix", withdrawn)

    def test_live_snapshot_requests_issue_state_reasons(self) -> None:
        with patch.object(self.renderer, "run_json", side_effect=[[], [[]]]) as run:
            self.renderer.load_snapshot(None, "pauljoda/Crest")

        command = run.call_args_list[0].args[0]
        fields = command[command.index("--json") + 1].split(",")
        self.assertIn("stateReason", fields)


if __name__ == "__main__":
    unittest.main()
