#!/usr/bin/env python3
"""Behavioral coverage for per-channel release-note publication cursors."""

from __future__ import annotations

import importlib.util
import json
import pathlib
import sys
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]


def load_script_module(name: str, filename: str):
    path = REPOSITORY_ROOT / "Scripts" / filename
    specification = importlib.util.spec_from_file_location(name, path)
    if specification is None or specification.loader is None:
        raise RuntimeError(f"Unable to load {path}")
    module = importlib.util.module_from_spec(specification)
    # Dataclasses look their module up while it loads.
    sys.modules[name] = module
    specification.loader.exec_module(module)
    return module


class ReleaseNotePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.catalog_module = load_script_module("release_note_catalog", "release_note_catalog.py")
        cls.publication = load_script_module(
            "release_note_publication",
            "release_note_publication.py",
        )

    def catalog(self):
        return self.catalog_module.assemble(
            [
                (
                    "0.1/0.1.1.json",
                    json.dumps(
                        {
                            "entries": [
                                {"id": "stable-boundary", "category": "internal", "message": "Stable boundary"},
                                {"id": "development-boundary", "category": "internal", "message": "Development boundary"},
                                {"id": "nightly-boundary", "category": "internal", "message": "Nightly boundary"},
                            ]
                        }
                    ),
                ),
                (
                    "0.1/0.1.2.json",
                    json.dumps({"entries": [{"id": "new-change", "category": "new", "message": "Open a second page"}]}),
                ),
            ]
        )

    def state_contents(self, **channels: str) -> str:
        return json.dumps(
            {
                "schemaVersion": 1,
                "channels": {
                    "stable": "stable-boundary",
                    "development": "development-boundary",
                    "nightly": "nightly-boundary",
                }
                | channels,
            }
        )

    def test_each_channel_advances_without_consuming_the_other_channels(self) -> None:
        catalog = self.catalog()
        state = self.publication.effective_publication_state(catalog, self.state_contents())

        advanced = self.publication.advance_channel(catalog, state, "nightly")

        self.assertEqual(advanced.channels["nightly"], "new-change")
        self.assertEqual(advanced.channels["development"], "development-boundary")
        self.assertEqual(advanced.channels["stable"], "stable-boundary")

    def test_state_rejects_a_cursor_that_is_not_in_the_catalog(self) -> None:
        with self.assertRaisesRegex(ValueError, "missing-entry"):
            self.publication.parse_publication_state(
                self.state_contents(development="missing-entry"),
                "state",
                self.catalog(),
            )


if __name__ == "__main__":
    unittest.main()
