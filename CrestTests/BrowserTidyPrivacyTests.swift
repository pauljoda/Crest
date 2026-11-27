import Foundation
import XCTest

@testable import Crest

/// What Tidy's on-device model may read: a tab's title, host and path, never
/// the query or fragment, which can carry tokens and personal details, and
/// nothing of a private window's tabs, which are never described or tidied.
@MainActor
final class BrowserTidyPrivacyTests: XCTestCase {
    func testTidyModelReadsTitleHostAndPathButNeverQueryOrFragment() throws {
        let address = try XCTUnwrap(
            URL(string: "https://mail.example.com/inbox/thread?token=secret-token&email=person@example.com#draft-7"))
        let candidate = try XCTUnwrap(TidyTabCandidate(tabID: UUID(), pageTitle: "Trip plans", address: address))

        XCTAssertEqual(candidate.modelDescription, "Trip plans — mail.example.com/inbox/thread")
        XCTAssertNil(TidyTabCandidate(tabID: UUID(), pageTitle: "Notes", address: URL(string: "about:blank")!))
    }

    func testAPrivateWindowOffersNoTabToTidy() throws {
        let tabs = (0..<TabTidying.minimumLooseTabCount).map { index in
            TabState.Seed(title: "Page \(index)", url: URL(string: "https://example.com/\(index)"), placement: .current)
        }
        let space = SpaceState.Seed(name: "Test", symbol: "circle", accent: .indigo, tabs: tabs)

        for kind in [WorkspaceKind.persistent, .private] {
            let browser = BrowserStore(
                seed: SessionState.Seed(spaces: [space]), showing: space.id, tabs: [space.id: tabs[0].id],
                workspaceKind: kind)
            let shown = try XCTUnwrap(browser.spaceModel(space.id))

            XCTAssertEqual(
                TabTidying.candidates(in: shown, of: browser).map(\.tabID), kind.isPrivate ? [] : tabs.map(\.id))
            XCTAssertEqual(TabTidying.candidateCount(in: shown, of: browser), kind.isPrivate ? 0 : tabs.count)
        }
    }
}
