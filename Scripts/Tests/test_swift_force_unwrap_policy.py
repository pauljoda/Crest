#!/usr/bin/env python3
"""Prevent crash-prone forced unwraps and casts from returning to app sources."""

from pathlib import Path
import re
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SOURCE_ROOTS = ("CrestShared", "CrestMac", "CrestMobile")
FORCED_OPERATION = re.compile(
    r"\btry!|\bas!\b|(?<![=!])(?:[A-Za-z0-9_]|\)|\]|\})!(?=[.\),\]\}:;]|$)",
    re.MULTILINE,
)


class SwiftForceUnwrapPolicyTests(unittest.TestCase):
    def test_app_sources_do_not_force_unwrap_cast_or_try(self) -> None:
        violations: list[str] = []
        for source_root in SOURCE_ROOTS:
            for path in (REPOSITORY_ROOT / source_root).rglob("*.swift"):
                for line_number, line in enumerate(path.read_text().splitlines(), 1):
                    if FORCED_OPERATION.search(line):
                        relative_path = path.relative_to(REPOSITORY_ROOT)
                        violations.append(f"{relative_path}:{line_number}: {line.strip()}")

        self.assertEqual(
            violations,
            [],
            "Forced Swift operations must be replaced with explicit failure handling:\n"
            + "\n".join(violations),
        )


if __name__ == "__main__":
    unittest.main()
