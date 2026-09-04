import AppKit
import Foundation
import XCTest

@testable import Crest

final class BrowserExtensionSidebarSwitcherMenuModelTests: XCTestCase {
    private let space = SpaceID()
    private let chatGPT = BrowserExtensionServiceClientID("chatgpt")!
    private let claude = BrowserExtensionServiceClientID("claude")!

    func testRowsCarryTheTitleTheCheckedPanelAndTheExtensionsOwnArtwork() throws {
        let artwork = Self.artwork()
        let model = BrowserExtensionSidebarSwitcherMenuModel(
            panels: [panel(chatGPT, title: "ChatGPT"), panel(claude, title: "Claude")],
            currentClientID: claude,
            icon: { $0.clientID == self.chatGPT ? artwork : nil }
        )

        XCTAssertTrue(model.presentsSwitcher)
        XCTAssertEqual(model.items.map(\.clientID), [chatGPT, claude])
        XCTAssertEqual(model.items.map(\.title), ["ChatGPT", "Claude"])
        XCTAssertEqual(model.items.map(\.isCurrent), [false, true])
        XCTAssertEqual(model.currentTitle, "Claude")

        let row = try XCTUnwrap(model.items.first)
        XCTAssertEqual(row.icon.size, BrowserExtensionSidebarSwitcherMenuModel.iconSize)
        XCTAssertFalse(row.icon.isTemplate, "Extension artwork keeps its own colors in the menu.")
        XCTAssertEqual(artwork.size, Self.artworkSize, "Resizing a row must not mutate the host's cached icon.")
        XCTAssertTrue(artwork.isTemplate)
    }

    func testAPanelWithoutArtworkFallsBackToTheTemplatedPuzzlePiece() throws {
        let model = BrowserExtensionSidebarSwitcherMenuModel(
            panels: [panel(chatGPT, title: "ChatGPT")], currentClientID: chatGPT, icon: { _ in nil }
        )

        let expected = try XCTUnwrap(
            NSImage(
                systemSymbolName: BrowserExtensionSidebarSwitcherMenuModel.fallbackSymbolName,
                accessibilityDescription: nil
            )
        )
        expected.size = BrowserExtensionSidebarSwitcherMenuModel.iconSize

        let row = try XCTUnwrap(model.items.first)
        XCTAssertEqual(row.icon.size, BrowserExtensionSidebarSwitcherMenuModel.iconSize)
        XCTAssertTrue(row.icon.isTemplate, "The fallback symbol follows the menu's label color.")
        XCTAssertEqual(row.icon.tiffRepresentation, expected.tiffRepresentation)
    }

    func testASoleAvailablePanelDoesNotEarnASwitcher() {
        let model = BrowserExtensionSidebarSwitcherMenuModel(
            panels: [panel(chatGPT, title: "ChatGPT")], currentClientID: chatGPT, icon: { _ in nil }
        )

        XCTAssertFalse(model.presentsSwitcher)
        XCTAssertEqual(model.currentTitle, "ChatGPT")
        XCTAssertFalse(
            BrowserExtensionSidebarSwitcherMenuModel(panels: [], currentClientID: nil, icon: { _ in nil })
                .presentsSwitcher
        )
    }

    func testAPanelThatIsNoLongerPresentedLeavesEveryRowUnchecked() {
        let model = BrowserExtensionSidebarSwitcherMenuModel(
            panels: [panel(chatGPT, title: "ChatGPT"), panel(claude, title: "Claude")],
            currentClientID: nil,
            icon: { _ in nil }
        )

        XCTAssertEqual(model.items.map(\.isCurrent), [false, false])
        XCTAssertNil(model.currentTitle)
    }

    private func panel(
        _ clientID: BrowserExtensionServiceClientID, title: String
    ) -> BrowserExtensionSidebarPanel {
        BrowserExtensionSidebarPanel(
            clientID: clientID,
            spaceID: space,
            documentURL: URL(string: "webkit-extension://\(clientID.rawValue)/panel.html"),
            path: "panel.html",
            title: title,
            icon: .packagePath("icon.png"),
            tabID: nil
        )
    }

    private static let artworkSize = NSSize(width: 64, height: 64)

    /// A representation-free image: the model only reads and rewrites the
    /// image's size and template flag, so nothing here has to be drawn.
    private static func artwork() -> NSImage {
        let image = NSImage(size: artworkSize)
        image.isTemplate = true
        return image
    }
}
