import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserFolderAppearanceTests: XCTestCase {
    func testFolderSymbolMutationRejectsStaleOwnershipAndSurvivesSync() throws {
        var first = BrowserSession.makeBlankSpace(number: 1)
        let folder = BrowserFolder(title: "Reading")
        first.folders = [folder]
        first.tabs[0].iconMode = .automatic
        var second = BrowserSession.makeBlankSpace(number: 2)
        second.tabs[0].iconMode = .automatic
        let session = BrowserSession(spaces: [first, second], selectedSpaceID: first.id)
        let browser = BrowserStore(session: session, persistence: InMemoryBrowserSessionPersistence())
        let emoji = BrowserIconSymbol.symbol(forEmoji: "📚")
        let stale = BrowserSpaceRuntimeAssignment(spaceID: first.id, profileID: UUID())
        XCTAssertFalse(browser.setFolderSymbol(folder.id, matching: stale, symbol: emoji))
        XCTAssertEqual(browser.session, session)
        XCTAssertTrue(browser.setFolderSymbol(folder.id, matching: .init(space: first), symbol: emoji))
        XCTAssertFalse(browser.setFolderSymbol(folder.id, matching: .init(space: first), symbol: emoji))
        let restored = try JSONDecoder().decode(BrowserSession.self, from: JSONEncoder().encode(browser.session))
        var journal = BrowserSyncJournal(deviceID: UUID())
        try journal.stage(session: restored, at: Date())
        let synced = try journal.materializedSession(applyingTo: session)
        XCTAssertEqual(synced.space(id: first.id)?.folders.first?.symbol, emoji)
        XCTAssertEqual(synced.space(id: first.id)?.tabs, first.tabs)
        XCTAssertEqual(synced.space(id: second.id), second)
    }

    func testLegacyBrandingRetainsSubtleFolderColorAndRoundTripsIntensity() throws {
        let original = BrowserSpaceBranding.legacy(accent: .indigo, symbol: "folder")
        XCTAssertEqual(original.folderColorIntensity, 0)
        var stronger = original
        stronger.folderColorIntensity = 1
        let decoded = try JSONDecoder().decode(
            BrowserSpaceBranding.self, from: JSONEncoder().encode(stronger))
        XCTAssertEqual(decoded.folderColorIntensity, 1)
        XCTAssertEqual(decoded.normalized().folderColorIntensity, 1)
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(stronger)) as? [String: Any])
        legacy.removeValue(forKey: "folderColorIntensity")
        let restored = try JSONDecoder().decode(
            BrowserSpaceBranding.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(restored.folderColorIntensity, 0)
        XCTAssertEqual(restored.colors, original.colors)
        XCTAssertEqual(restored.renderingVersion, original.renderingVersion)
    }

}
