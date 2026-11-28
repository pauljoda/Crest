"""Protect which app builds a change runs, so a change never skips the build it can break."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "ci-changed-areas.py"
spec = importlib.util.spec_from_file_location("ci_changed_areas", SCRIPT)
areas = importlib.util.module_from_spec(spec)
sys.modules["ci_changed_areas"] = areas
spec.loader.exec_module(areas)


def builds(*paths: str) -> dict[str, bool]:
    """The builds the change of `paths` runs, as the script prints them."""
    output = io.StringIO()
    with mock.patch.object(areas, "changed_paths", return_value=list(paths)), \
            contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
        areas.main()
    return {key: value == "true" for key, value in (line.split("=") for line in output.getvalue().split())}


class ChangedAreasTests(unittest.TestCase):
    def test_desktop_shell_change_builds_only_the_desktop(self):
        self.assertEqual(builds("CrestDesktop/ui/app/src/menus.ts", "Scripts/package-windows.py"),
                         {"mac": False, "ios": False, "desktop": True})

    def test_apple_change_skips_the_desktop(self):
        self.assertEqual(builds("CrestMac/App/BrowserMacApplication.swift"), {"mac": True, "ios": False, "desktop": False})
        self.assertEqual(builds("CrestShared/Infrastructure/Core/CrestCore.swift"),
                         {"mac": True, "ios": True, "desktop": False})

    def test_core_change_builds_every_app(self):
        self.assertEqual(builds("CrestCore/src/CrestCore/Application/App/CrestApp.cs"),
                         {"mac": True, "ios": True, "desktop": True})

    def test_documentation_builds_nothing(self):
        self.assertEqual(builds("README.md", "Documentation/ARCHITECTURE.md"), {"mac": False, "ios": False, "desktop": False})

    def test_release_notes_alone_build_every_app(self):
        self.assertEqual(builds("Documentation/ReleaseNotes/changes/example.json"),
                         {"mac": True, "ios": True, "desktop": True})

    def test_unknown_change_builds_every_app(self):
        output = io.StringIO()
        with mock.patch.object(areas, "changed_paths", return_value=None), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(io.StringIO()):
            areas.main()
        self.assertEqual(output.getvalue().split(), ["mac=true", "ios=true", "desktop=true"])


if __name__ == "__main__":
    unittest.main()
