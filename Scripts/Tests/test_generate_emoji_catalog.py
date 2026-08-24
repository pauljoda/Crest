#!/usr/bin/env python3
"""Regression coverage for Crest's official Unicode emoji catalog generator."""

from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
GENERATOR_PATH = REPOSITORY_ROOT / "Scripts" / "generate-emoji-catalog.py"
SPEC = importlib.util.spec_from_file_location("generate_emoji_catalog", GENERATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
GENERATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GENERATOR)


FIXTURE = """# emoji-test.txt
# Version: 17.0
# group: Smileys & Emotion
# subgroup: face-smiling
1F600 ; fully-qualified # 😀 E1.0 grinning face
263A ; unqualified # ☺ E0.6 smiling face
# group: People & Body
# subgroup: handshake
1FAF1 1F3FF 200D 1FAF2 1F3FB ; fully-qualified # 🫱🏿‍🫲🏻 E14.0 handshake: dark skin tone, light skin tone
1F3FF ; component # 🏿 E1.0 dark skin tone
# group: Flags
# subgroup: subdivision-flag
1F3F4 E0067 E0062 E0065 E006E E0067 E007F ; fully-qualified # 🏴 E5.0 flag: England
"""


class EmojiCatalogGeneratorTests(unittest.TestCase):
    def test_parses_only_fully_qualified_sequences_and_maps_categories(self) -> None:
        version, entries = GENERATOR.parse_emoji_test(FIXTURE)

        self.assertEqual(version, "17.0")
        self.assertEqual(len(entries), 3)
        self.assertEqual(
            [entry["category"] for entry in entries],
            ["people", "people", "flags"],
        )
        self.assertEqual(entries[0]["name"], "Grinning face")

    def test_preserves_mixed_tone_zwj_and_subdivision_flag_sequences(self) -> None:
        _, entries = GENERATOR.parse_emoji_test(FIXTURE)

        self.assertEqual(entries[1]["emoji"], "🫱🏿‍🫲🏻")
        self.assertEqual(len(entries[1]["emoji"]), 5)
        self.assertEqual(
            [f"{ord(scalar):X}" for scalar in entries[2]["emoji"]],
            ["1F3F4", "E0067", "E0062", "E0065", "E006E", "E0067", "E007F"],
        )

    def test_catalog_metadata_and_generated_source_are_deterministic(self) -> None:
        source_url = "https://example.test/emoji-test.txt"
        catalog = GENERATOR.build_catalog(FIXTURE, source_url)

        self.assertEqual(catalog["metadata"]["unicodeVersion"], "17.0")
        self.assertEqual(catalog["metadata"]["sourceURL"], source_url)
        self.assertEqual(catalog["metadata"]["fullyQualifiedCount"], 3)
        self.assertEqual(
            catalog["metadata"]["sourceSHA256"],
            hashlib.sha256(FIXTURE.encode("utf-8")).hexdigest(),
        )
        self.assertEqual(
            GENERATOR.render_swift(catalog),
            GENERATOR.render_swift(GENERATOR.build_catalog(FIXTURE, source_url)),
        )


if __name__ == "__main__":
    unittest.main()
