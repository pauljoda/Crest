import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserFolderAppearanceTests: XCTestCase {
    func testFolderSymbolMutationRejectsStaleOwnershipAndSurvivesSync() async throws {
        var first = BrowserSession.makeBlankSpace(number: 1)
        let folder = BrowserFolder(title: "Reading")
        first.folders = [folder]
        first.tabs[0].storedIconMode = .automatic
        var second = BrowserSession.makeBlankSpace(number: 2)
        second.tabs[0].storedIconMode = .automatic
        let session = BrowserSession(spaces: [first, second], defaultSpaceID: first.id)
        let harness = try await BrowserStoredSessionHarness.uploaded(session)
        let browser = harness.store
        // Another device that holds what this one uploaded.
        let other = try await harness.joiningDevice()
        let received = other.store.session
        let emoji = BrowserIconSymbol.symbol(forEmoji: "📚")
        let stale = BrowserSpaceRuntimeAssignment(spaceID: first.id, profileID: UUID())
        let opened = browser.session
        XCTAssertFalse(browser.setFolderSymbol(folder.id, matching: stale, symbol: emoji))
        XCTAssertEqual(browser.session, opened)
        XCTAssertTrue(browser.setFolderSymbol(folder.id, matching: .init(space: first), symbol: emoji))
        XCTAssertFalse(browser.setFolderSymbol(folder.id, matching: .init(space: first), symbol: emoji))

        try other.deliverNow(MergeSyncRecords(records: try await harness.pendingRecords()))

        let synced = other.store.session
        XCTAssertEqual(synced.space(id: first.id)?.folders.first?.symbol, emoji)
        XCTAssertEqual(synced.space(id: first.id)?.tabs, received.space(id: first.id)?.tabs)
        XCTAssertEqual(synced.space(id: second.id), received.space(id: second.id))
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
