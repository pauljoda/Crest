import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionSidebarRegistryTests: XCTestCase {
    func testManifestDefaultsAndPartialUpdatesResolveWithoutLosingPath() {
        var registry = BrowserExtensionSidebarRegistry(
            defaults: .init(flavor: .sidePanel, path: "panel.html"), displayName: "ChatGPT"
        )
        registry.merge(.init(isEnabled: false), at: .default)
        XCTAssertEqual(registry.resolved(for: nil).path, "panel.html")
        XCTAssertFalse(registry.resolved(for: nil).presentsPanel)
        registry.merge(.init(isEnabled: true), at: .default)
        XCTAssertTrue(registry.resolved(for: nil).presentsPanel)
        XCTAssertEqual(registry.resolved(for: nil).title, "ChatGPT")
    }

    func testTabAndWindowOverridesInheritAndResetIndependently() {
        let tab = TabID()
        var registry = BrowserExtensionSidebarRegistry(
            defaults: .init(flavor: .sidebarAction, path: "panel.html", title: "Manifest"),
            displayName: "Extension"
        )
        registry.merge(.init(title: "Global"), at: .default)
        registry.merge(.init(title: "Window"), at: .window)
        registry.merge(.init(path: "tab.html", title: "Tab"), at: .tab(tab))
        XCTAssertEqual(registry.resolved(for: tab).title, "Tab")
        XCTAssertEqual(registry.resolved(for: tab).scope, .tab(tab))
        registry.clearTitle(at: .tab(tab))
        XCTAssertEqual(registry.resolved(for: tab).title, "Window")
        XCTAssertEqual(registry.resolved(at: .default).title, "Global")
        XCTAssertEqual(registry.resolved(for: TabID()).path, "panel.html")
        registry.repair(liveTabs: [])
        XCTAssertEqual(registry.resolved(for: tab).path, "panel.html")
    }

    func testEmptyPathDisablesPanelButMissingPathInherits() {
        let tab = TabID()
        var registry = BrowserExtensionSidebarRegistry(
            defaults: .init(flavor: .sidePanel, path: "panel.html"), displayName: "Extension"
        )
        registry.merge(.init(isEnabled: true), at: .tab(tab))
        XCTAssertEqual(registry.resolved(for: tab).scope, .default)
        registry.merge(.init(path: ""), at: .tab(tab))
        XCTAssertFalse(registry.resolved(for: tab).presentsPanel)
    }

    func testManifestFlavorAndUnresolvedLocalization() throws {
        let manifest: [String: Any] = [
            "manifest_version": 3,
            "side_panel": ["default_path": "chrome.html"],
            "sidebar_action": ["default_panel": "firefox.html", "default_title": "__MSG_title__"],
        ]
        let chrome = try XCTUnwrap(
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: manifest, referenceEnvironment: .chromium
            ))
        let firefox = try XCTUnwrap(
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: manifest, referenceEnvironment: .firefox
            ))
        XCTAssertEqual(chrome.path, "chrome.html")
        XCTAssertEqual(firefox.path, "firefox.html")
        XCTAssertNil(firefox.title)
        XCTAssertTrue(firefox.opensAtInstall)
        XCTAssertTrue(BrowserExtensionSidebarManifestPolicy.declaresSidebar(manifest: manifest))
        XCTAssertNil(
            BrowserExtensionSidebarManifestPolicy.defaults(
                manifest: ["manifest_version": 2, "side_panel": ["default_path": "panel.html"]],
                referenceEnvironment: .chromium
            ))
    }
}
