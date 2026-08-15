#!/usr/bin/env python3
"""Platform ownership contracts for default-browser behavior."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DOMAIN_ROOT = REPOSITORY_ROOT / "CrestShared/Domain/BrowserDefaultBrowser"
APPLICATION_CONTROLLER = (
    REPOSITORY_ROOT
    / "CrestShared/Application/BrowserDefaultBrowser/BrowserDefaultBrowserController.swift"
)


class DefaultBrowserPlatformOwnershipTests(unittest.TestCase):
    def test_default_browser_models_and_controller_use_focused_files(self) -> None:
        for relative_path in (
            "Models/BrowserDefaultBrowserStatus.swift",
            "Models/BrowserDefaultBrowserRequestStyle.swift",
            "Policies/BrowserExternalURLPolicy.swift",
        ):
            with self.subTest(relative_path=relative_path):
                self.assertTrue((DOMAIN_ROOT / relative_path).is_file())

        self.assertTrue(APPLICATION_CONTROLLER.is_file())

        self.assertFalse(
            (REPOSITORY_ROOT / "CrestShared/Domain/BrowserDefaultBrowser.swift").exists()
        )
        self.assertFalse(
            (DOMAIN_ROOT / "BrowserDefaultBrowserController.swift").exists()
        )

    def test_shared_default_browser_sources_have_no_platform_dependencies(self) -> None:
        for path in DOMAIN_ROOT.rglob("*.swift"):
            source = path.read_text()
            with self.subTest(path=path.relative_to(REPOSITORY_ROOT)):
                self.assertNotIn("#if os(", source)
                self.assertNotIn("import AppKit", source)
                self.assertNotIn("import UIKit", source)
                self.assertNotIn("BrowserPlatformDefaultBrowserSystem", source)
                self.assertNotIn("BrowserPlatformDefaultBrowserErrorPolicy", source)

        controller_source = APPLICATION_CONTROLLER.read_text()
        self.assertNotIn("import AppKit", controller_source)
        self.assertNotIn("import UIKit", controller_source)
        self.assertIn("BrowserPlatformDefaultBrowserSystem", controller_source)
        self.assertIn("BrowserPlatformDefaultBrowserErrorPolicy", controller_source)
        for injected_seam in (
            "statusCheck: @escaping StatusCheck",
            "defaultRequest: @escaping DefaultRequest",
            "settingsOpener: @escaping SettingsOpener",
        ):
            with self.subTest(injected_seam=injected_seam):
                self.assertIn(injected_seam, controller_source)

    def test_each_platform_owns_system_and_error_policy_implementations(self) -> None:
        for platform_root in ("CrestMac", "CrestMobile"):
            for filename in (
                "BrowserPlatformDefaultBrowserSystem.swift",
                "BrowserPlatformDefaultBrowserErrorPolicy.swift",
            ):
                relative_path = (
                    f"{platform_root}/Infrastructure/BrowserDefaultBrowser/{filename}"
                )
                with self.subTest(relative_path=relative_path):
                    self.assertTrue((REPOSITORY_ROOT / relative_path).is_file())
                    self.assertFalse(
                        (
                            REPOSITORY_ROOT
                            / platform_root
                            / "Domain/BrowserDefaultBrowser"
                            / filename
                        ).exists()
                    )


if __name__ == "__main__":
    unittest.main()
