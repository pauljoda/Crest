#!/usr/bin/env python3
"""Keep platform implementations out of the shared Swift source root."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SHARED_ROOT = REPOSITORY_ROOT / "CrestShared"
FORBIDDEN_MARKERS = (
    "import AppKit",
    "import UIKit",
    "#if os(macOS)",
    "#if os(iOS)",
    "#elseif os(macOS)",
    "#elseif os(iOS)",
)


class SharedPlatformNeutralityTests(unittest.TestCase):
    def test_shared_swift_sources_have_no_native_platform_branches(self) -> None:
        violations: list[str] = []
        for path in SHARED_ROOT.rglob("*.swift"):
            source = path.read_text()
            for marker in FORBIDDEN_MARKERS:
                if marker in source:
                    relative_path = path.relative_to(REPOSITORY_ROOT)
                    violations.append(f"{relative_path}: {marker}")

        self.assertEqual(
            violations,
            [],
            "Move native platform behavior to CrestMac or CrestMobile:\n"
            + "\n".join(violations),
        )


if __name__ == "__main__":
    unittest.main()
