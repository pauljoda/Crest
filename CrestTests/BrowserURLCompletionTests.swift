import Foundation
import XCTest

@testable import Crest

final class BrowserURLCompletionTests: XCTestCase {
    func testCompletesOnlyLiteralHostAndCaseSensitivePathPrefixes() throws {
        let space = fixture(urls: ["https://example.com/Docs/Start"])
        XCTAssertEqual(completion("exa", space)?.suffix, "mple.com/Docs/Start")
        XCTAssertEqual(completion("example.com/Docs/S", space)?.suffix, "tart")
        XCTAssertNil(completion("ample", space))
        XCTAssertNil(completion("example.com/docs", space))
        XCTAssertNil(completion("example.com/Docs/Start", space))
        XCTAssertNil(completion("find example", space))
        XCTAssertNil(completion("https://", space))
        XCTAssertNil(completion("?example", space))
    }

    func testExactAddressPreventsLongerCandidateFromTakingOver() {
        let space = fixture(urls: ["https://example.com", "https://example.com/longer"])
        XCTAssertNil(completion("example.com", space))
        XCTAssertNil(completion("https://example.com", space))
    }

    func testHostPathMatchesRetainTheLocalAddressQueryAndFragment() {
        let space = fixture(urls: ["https://example.com/docs?language=swift#start"])
        XCTAssertEqual(completion("example.com/do", space)?.completedQuery, "example.com/docs?language=swift#start")
        XCTAssertNil(completion("example.com/docs?language", space))
        XCTAssertNil(completion("example.com/docs#", space))
        XCTAssertEqual(
            completion("example.com/", fixture(urls: ["https://example.com/?q=swift"]))?.completedQuery,
            "example.com/?q=swift")
    }

    func testInsecureHistoryKeepsItsSchemeWhenAccepted() throws {
        let proposal = try XCTUnwrap(completion("exa", fixture(urls: ["http://example.com/path"])))
        XCTAssertEqual(proposal.completedQuery, "example.com/path")
        XCTAssertEqual(proposal.acceptedQuery, "http://example.com/path")
        XCTAssertEqual(proposal.insertionRange, NSRange(location: 0, length: 3))
    }

    func testSchemeAndCredentialsAreNeverRewrittenOrDisclosed() {
        let space = fixture(urls: [
            "http://example.com/path", "https://user:secret@example.net/path", "file:///example",
        ])
        XCTAssertNil(completion("https://exa", space))
        XCTAssertNil(completion("example.n", space))
        XCTAssertEqual(completion("http://exa", space)?.completedQuery, "http://example.com/path")
    }

    func testRankingIsStableAcrossInputOrderAndUsesRecency() {
        var space = fixture(urls: ["https://example.org/path", "https://example.com/path"])
        space.tabs[0].lastActivatedAt = Date(timeIntervalSince1970: 10)
        space.tabs[1].lastActivatedAt = Date(timeIntervalSince1970: 20)
        XCTAssertEqual(completion("exa", space)?.completedQuery, "example.com/path")
        space.tabs.reverse()
        XCTAssertEqual(completion("exa", space)?.completedQuery, "example.com/path")
    }

    func testCandidatesAreConfinedToTheProvidedSpace() {
        let current = fixture(urls: ["https://current.example/path"])
        let other = fixture(urls: ["https://private.example/path"])
        XCTAssertNil(completion("private", current))
        XCTAssertEqual(completion("private", other)?.completedQuery, "private.example/path")
        XCTAssertNil(BrowserURLCompletion.proposal(query: "current", space: nil))
    }

    func testSelectionCompositionAndDeletionSuppressProposal() {
        var editing = BrowserURLCompletionEditingState()
        editing.update(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertTrue(editing.canPropose(for: "exa"))
        editing.update(text: "exa", selection: NSRange(location: 2, length: 0), isComposing: false)
        XCTAssertFalse(editing.canPropose(for: "exa"))
        editing.update(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: true)
        XCTAssertFalse(editing.canPropose(for: "exa"))
        editing.update(text: "ex", selection: NSRange(location: 2, length: 0), isComposing: false)
        XCTAssertFalse(editing.canPropose(for: "ex"))
        editing.update(text: "exa", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertTrue(editing.canPropose(for: "exa"))
        editing.reject()
        XCTAssertFalse(editing.canPropose(for: "exa"))
    }

    func testOpenSavedAndHistorySignalsAndHistoryOnlyCompletion() {
        var space = fixture(urls: ["https://example.open/path", "https://example.saved/path"])
        space.tabs[1].placement = .saved
        space.tabs[1].savedURL = URL(string: "https://example.saved/root")
        space.history = [
            BrowserHistoryEntry(
                url: URL(string: "https://example.history/path")!, title: "History", firstVisitedAt: .distantPast,
                lastVisitedAt: .distantFuture, visitCount: 50)
        ]
        XCTAssertEqual(completion("exa", space)?.completedQuery, "example.open/path")
        XCTAssertEqual(completion("example.saved/r", space)?.suffix, "oot")
        space.tabs.removeAll()
        XCTAssertEqual(completion("exa", space)?.completedQuery, "example.history/path")
    }

    func testUnicodeSelectionUsesUTF16AndQueryChangesInvalidateEditingSnapshot() {
        var editing = BrowserURLCompletionEditingState()
        editing.update(text: "é😀", selection: NSRange(location: 3, length: 0), isComposing: false)
        XCTAssertTrue(editing.canPropose(for: "é😀"))
        XCTAssertFalse(editing.canPropose(for: "é😀a"))
        editing.update(text: "é😀", selection: NSRange(location: 0, length: 3), isComposing: false)
        XCTAssertFalse(editing.canPropose(for: "é😀"))
    }

    private func completion(_ query: String, _ space: BrowserSpace) -> BrowserURLCompletion? {
        BrowserURLCompletion.proposal(query: query, space: space)
    }

    private func fixture(urls: [String]) -> BrowserSpace {
        BrowserSpace(
            id: SpaceID(), profile: BrowsingProfile(), name: "Completion", symbol: "globe", accent: .indigo,
            folders: [],
            tabs: urls.map {
                BrowserTab(
                    title: "Page", url: URL(string: $0), placement: .current,
                    lastActivatedAt: Date(timeIntervalSince1970: 0))
            }, selectedTabID: nil)
    }
}
