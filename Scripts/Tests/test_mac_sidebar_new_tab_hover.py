#!/usr/bin/env python3
"""Contracts for the macOS sidebar New Tab interaction surface."""

from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]


class MacSidebarNewTabHoverTests(unittest.TestCase):
    def test_new_tab_row_is_an_extracted_sidebar_component(self) -> None:
        sidebar = (
            REPOSITORY_ROOT / "CrestMac/Features/Sidebar/BrowserSidebar.swift"
        ).read_text()
        component = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Sidebar/Components/NewTabRow.swift"
        )

        self.assertTrue(component.is_file())
        self.assertNotIn("private struct NewTabRow", sidebar)

    def test_new_tab_row_uses_the_shared_hover_state_decorator(self) -> None:
        source = (
            REPOSITORY_ROOT
            / "CrestMac/Features/Sidebar/Components/NewTabRow.swift"
        ).read_text()

        self.assertIn(".crestHoverSurface(", source)
        self.assertNotIn(".onHover", source)
        self.assertIn("#Preview", source)

    def test_shared_hover_decorator_owns_hover_state(self) -> None:
        modifier = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestInteractiveSurface/Modifiers/CrestHoverSurfaceModifier.swift"
        ).read_text()
        extension = (
            REPOSITORY_ROOT
            / "CrestShared/DesignSystem/Components/CrestInteractiveSurface/Extensions/View+CrestHoverSurface.swift"
        ).read_text()

        self.assertIn("@State private var isHovering", modifier)
        self.assertIn(".crestInteractiveSurface(", modifier)
        self.assertIn(".onHover", modifier)
        self.assertIn("func crestHoverSurface(", extension)


if __name__ == "__main__":
    unittest.main()
