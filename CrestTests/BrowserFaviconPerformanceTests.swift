import Foundation
import XCTest

@testable import Crest

final class BrowserFaviconPerformanceTests: XCTestCase {
    func testPayloadIdentityReadsEveryByteInsteadOfSampledOffsets() {
        let originalBytes = [UInt8](repeating: 0, count: 64)
        var changedBytes = originalBytes
        // The identity this replaced sampled byte ranges beginning at 0, 18, 37,
        // and 56 for a 64-byte payload. Byte 10 was invisible.
        changedBytes[10] = 1
        let original = Data(originalBytes)
        let changed = Data(changedBytes)

        XCTAssertEqual(
            BrowserFaviconPayloadIdentity(hashing: original),
            BrowserFaviconPayloadIdentity(hashing: original)
        )
        XCTAssertNotEqual(
            BrowserFaviconPayloadIdentity(hashing: original),
            BrowserFaviconPayloadIdentity(hashing: changed)
        )
        // A trailing difference is just as visible as a leading one.
        var tailBytes = originalBytes
        tailBytes[63] = 1
        XCTAssertNotEqual(
            BrowserFaviconPayloadIdentity(hashing: original),
            BrowserFaviconPayloadIdentity(hashing: Data(tailBytes))
        )
    }

    func testATabFingerprintsItsFaviconOnceSoRenderIdentitiesStayConstantWork() {
        let payload = Data((0..<64 * 1_024).map { UInt8(truncatingIfNeeded: $0) })
        var tab = BrowserTab(
            title: "Crest",
            url: URL(string: "https://crest.example/"),
            placement: .current
        )
        XCTAssertNil(tab.faviconPayloadIdentity)

        tab.faviconData = payload

        XCTAssertEqual(
            tab.faviconPayloadIdentity,
            BrowserFaviconPayloadIdentity(hashing: payload),
            "Assigning the bytes is what fingerprints them."
        )
        XCTAssertEqual(tab.displayFaviconPayloadIdentity, tab.faviconPayloadIdentity)

        // SwiftUI rebuilds this identity on every view update, per visible tab
        // row. It must never touch the payload again.
        let first = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: nil,
            maximumPixelSize: 32
        )
        let second = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: nil,
            maximumPixelSize: 32
        )
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.payload, tab.faviconPayloadIdentity)

        tab.faviconData = nil
        XCTAssertNil(tab.faviconPayloadIdentity)
    }

    func testADistinctFaviconProducesADistinctRenderIdentityForTheSameTab() throws {
        let url = try XCTUnwrap(URL(string: "https://crest.example/"))
        var tab = BrowserTab(title: "Crest", url: url, placement: .current)
        tab.faviconData = Data([UInt8](repeating: 3, count: 2_048))
        let before = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: nil,
            maximumPixelSize: 32
        )

        // Same tab, same page, same length — only the bytes moved.
        var replacement = [UInt8](repeating: 3, count: 2_048)
        replacement[1_024] = 4
        tab.faviconData = Data(replacement)

        XCTAssertNotEqual(
            BrowserFaviconTaskIdentityPolicy.identity(
                for: tab,
                profileID: nil,
                maximumPixelSize: 32
            ),
            before,
            "A new icon has to restart the render task; aliasing here shows a stale icon."
        )
    }

    func testAnEmojiTabCarriesNoPayloadIdentityEvenWhileItHoldsBytes() throws {
        let url = try XCTUnwrap(URL(string: "https://crest.example/"))
        var tab = BrowserTab(
            title: "Research",
            url: url,
            symbol: BrowserTab.symbol(forEmoji: "🧭"),
            iconMode: .emoji,
            placement: .current
        )
        tab.faviconData = Data([UInt8](repeating: 9, count: 128))

        XCTAssertNotNil(tab.faviconPayloadIdentity)
        XCTAssertNil(
            tab.displayFaviconPayloadIdentity,
            "An emoji tab renders no image, so its render identity carries no payload."
        )
        XCTAssertNil(
            BrowserFaviconTaskIdentityPolicy.identity(
                for: tab,
                profileID: nil,
                maximumPixelSize: 32
            ).payload
        )
    }

    func testAFingerprintSurvivesAStoredSessionRoundTripWithoutBeingStored() throws {
        let payload = Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        var tab = BrowserTab(
            title: "Crest",
            url: URL(string: "https://crest.example/"),
            placement: .current
        )
        tab.faviconData = payload

        let encoded = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(BrowserTab.self, from: encoded)
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertFalse(
            json.keys.contains { $0.localizedCaseInsensitiveContains("payloadidentity") },
            "The fingerprint is derived, so storing it could only ever go stale."
        )
        XCTAssertEqual(decoded.faviconPayloadIdentity, tab.faviconPayloadIdentity)
        XCTAssertEqual(decoded, tab)
    }

    func testDecodedImageCacheReusesTheDecodedThumbnail() async throws {
        let base64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        let data = try XCTUnwrap(Data(base64Encoded: base64))
        await BrowserFaviconImageCache.shared.removeAll()

        let firstResult = await BrowserFaviconImageDecoder.decode(
            data,
            maximumPixelSize: 64
        )
        let secondResult = await BrowserFaviconImageDecoder.decode(
            data,
            maximumPixelSize: 64
        )
        let first = try XCTUnwrap(firstResult)
        let second = try XCTUnwrap(secondResult)

        XCTAssertTrue(first === second)
        let cachedImageCount = await BrowserFaviconImageCache.shared.cachedImageCount
        XCTAssertEqual(cachedImageCount, 1)
    }

    func testPreviewFixtureUsesInlineBytesThatDecodeThroughImageIO() {
        XCTAssertNotNil(
            BrowserFaviconImageDecoder.decodeSynchronously(
                TabFaviconPreviewFixture.imageData,
                maximumPixelSize: 64
            )
        )
    }
}
