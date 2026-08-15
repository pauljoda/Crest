#!/usr/bin/env python3
"""Contracts for Crest-authored SwiftUI motion."""

from __future__ import annotations

import pathlib
import re
import unittest


REPOSITORY_ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_ROOTS = ("CrestShared", "CrestMac", "CrestMobile")
MOTION_TOKEN = pathlib.Path(
    "CrestShared/DesignSystem/Tokens/CrestMotion.swift"
)
NUMERIC_DURATION_ANIMATION = re.compile(
    r"\.(?:easeIn|easeOut|easeInOut|linear|snappy|smooth|spring)"
    r"\([^)]*?duration\s*:\s*(?:\d+(?:\.\d*)?|\.\d+)",
    re.DOTALL,
)
RAW_ANIMATION_APPLICATION = re.compile(
    r"(?:\.animation\(\s*\.|withAnimation\(\s*\.|withAnimation\s*\{)",
    re.DOTALL,
)


class CrestMotionTokenTests(unittest.TestCase):
    def test_authored_animation_durations_are_centralized(self) -> None:
        violations: list[str] = []

        for source_root in SOURCE_ROOTS:
            for source in (REPOSITORY_ROOT / source_root).rglob("*.swift"):
                if source.relative_to(REPOSITORY_ROOT) == MOTION_TOKEN:
                    continue

                contents = source.read_text()
                for match in NUMERIC_DURATION_ANIMATION.finditer(contents):
                    line = contents.count("\n", 0, match.start()) + 1
                    violations.append(
                        f"{source.relative_to(REPOSITORY_ROOT)}:{line}"
                    )

        self.assertEqual(
            violations,
            [],
            "Move numeric SwiftUI animation durations into CrestMotion: "
            + ", ".join(violations),
        )

    def test_raw_animations_are_not_applied_without_accessibility_policy(self) -> None:
        violations: list[str] = []

        for source_root in SOURCE_ROOTS:
            for source in (REPOSITORY_ROOT / source_root).rglob("*.swift"):
                if source.relative_to(REPOSITORY_ROOT) == MOTION_TOKEN:
                    continue

                contents = source.read_text()
                for match in RAW_ANIMATION_APPLICATION.finditer(contents):
                    line = contents.count("\n", 0, match.start()) + 1
                    violations.append(
                        f"{source.relative_to(REPOSITORY_ROOT)}:{line}"
                    )

        self.assertEqual(
            violations,
            [],
            "Route raw animations through CrestMotion and "
            "BrowserVisualAccessibilityPolicy: "
            + ", ".join(violations),
        )


if __name__ == "__main__":
    unittest.main()
