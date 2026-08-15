import Foundation
import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserFaviconRenderSafetyTests: XCTestCase {
    func testStartPageAndEmojiRequestsNeverInvokeNetworkFallback() async {
        let fallback = RecordingFallback()
        let profileID = fixedUUID(tail: 0x90)
        let tabs = [
            BrowserTab.startPage(
                id: tabID(tail: 0x10),
                lastActivatedAt: .distantPast
            ),
            BrowserTab(
                id: tabID(tail: 0x20),
                title: "Emoji",
                url: URL(string: "https://emoji.invalid/page"),
                symbol: BrowserTab.symbol(forEmoji: "🧭"),
                iconMode: .emoji,
                placement: .current,
                lastActivatedAt: .distantPast
            ),
        ]

        for tab in tabs {
            let request = BrowserFaviconTaskIdentityPolicy.renderRequest(
                for: tab,
                profileID: profileID,
                maximumPixelSize: 64
            )
            let result = await BrowserFaviconRenderLoader.decode(
                request,
                fallbackData: fallback.data
            )
            XCTAssertNil(result)
        }

        let requestCount = await fallback.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testRenderedImageIsQualifiedByTheFullRenderRequestIdentity() {
        let tab = makeTab(
            id: tabID(tail: 0x30),
            url: URL(string: "https://identity.invalid/original"),
            data: Data([0x01, 0x02, 0x03]),
            iconMode: .automatic
        )
        let original = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: fixedUUID(tail: 0xA0),
            maximumPixelSize: 64
        )
        let replacementProfile = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: fixedUUID(tail: 0xA1),
            maximumPixelSize: 64
        )
        let rendered = BrowserFaviconRenderedImage(
            requestIdentity: original,
            image: Image(systemName: "shield.fill")
        )

        XCTAssertNotNil(rendered.image(matching: original))
        XCTAssertNil(rendered.image(matching: replacementProfile))
    }

    func testCancelledOlderRequestStartingLateCannotClearOrReplaceNewerImage() {
        let tab = makeTab(
            id: tabID(tail: 0x31),
            url: URL(string: "https://identity.invalid/race"),
            data: Data([0x01, 0x02, 0x03]),
            iconMode: .automatic
        )
        let older = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: fixedUUID(tail: 0xA2),
            maximumPixelSize: 64
        )
        let newer = BrowserFaviconTaskIdentityPolicy.identity(
            for: tab,
            profileID: fixedUUID(tail: 0xA3),
            maximumPixelSize: 64
        )
        var state = BrowserFaviconRenderState()

        state.begin(older, isCancelled: false)
        state.begin(newer, isCancelled: false)
        state.publish(
            Image(systemName: "checkmark.seal.fill"),
            for: newer,
            isCancelled: false
        )
        state.begin(older, isCancelled: true)
        state.publish(
            Image(systemName: "xmark.seal.fill"),
            for: older,
            isCancelled: true
        )

        XCTAssertNotNil(state.renderedImage?.image(matching: newer))
        XCTAssertNil(state.renderedImage?.image(matching: older))
    }

    func testTaskIdentityIncludesTabProfileURLModePayloadAndPixelSize() {
        let baseTab = makeTab(
            id: tabID(tail: 0x40),
            url: URL(string: "https://identity.invalid/base"),
            data: Data([0x10, 0x20, 0x30]),
            iconMode: .automatic
        )
        let profileID = fixedUUID(tail: 0xB0)
        let base = BrowserFaviconTaskIdentityPolicy.identity(
            for: baseTab,
            profileID: profileID,
            maximumPixelSize: 64
        )
        let variations = [
            BrowserFaviconTaskIdentityPolicy.identity(
                for: makeTab(
                    id: tabID(tail: 0x41),
                    url: baseTab.url,
                    data: baseTab.faviconData,
                    iconMode: .automatic
                ),
                profileID: profileID,
                maximumPixelSize: 64
            ),
            BrowserFaviconTaskIdentityPolicy.identity(
                for: baseTab,
                profileID: fixedUUID(tail: 0xB1),
                maximumPixelSize: 64
            ),
            BrowserFaviconTaskIdentityPolicy.identity(
                for: makeTab(
                    id: baseTab.id,
                    url: URL(string: "https://identity.invalid/changed"),
                    data: baseTab.faviconData,
                    iconMode: .automatic
                ),
                profileID: profileID,
                maximumPixelSize: 64
            ),
            BrowserFaviconTaskIdentityPolicy.identity(
                for: makeTab(
                    id: baseTab.id,
                    url: baseTab.url,
                    data: baseTab.faviconData,
                    iconMode: .pulled
                ),
                profileID: profileID,
                maximumPixelSize: 64
            ),
            BrowserFaviconTaskIdentityPolicy.identity(
                for: makeTab(
                    id: baseTab.id,
                    url: baseTab.url,
                    data: Data([0x10, 0x20, 0x31]),
                    iconMode: .automatic
                ),
                profileID: profileID,
                maximumPixelSize: 64
            ),
            BrowserFaviconTaskIdentityPolicy.identity(
                for: baseTab,
                profileID: profileID,
                maximumPixelSize: 65
            ),
        ]

        for variation in variations {
            XCTAssertNotEqual(base, variation)
        }
    }

    private func makeTab(
        id: TabID,
        url: URL?,
        data: Data?,
        iconMode: BrowserTabIconMode
    ) -> BrowserTab {
        BrowserTab(
            id: id,
            title: "Identity",
            url: url,
            faviconData: data,
            iconMode: iconMode,
            placement: .current,
            lastActivatedAt: .distantPast
        )
    }

    private func tabID(tail: UInt8) -> TabID {
        TabID(rawValue: fixedUUID(tail: tail))
    }

    private func fixedUUID(tail: UInt8) -> UUID {
        UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tail))
    }

    private actor RecordingFallback {
        private(set) var requestCount = 0

        func data(pageURL _: URL, profileID _: UUID) async -> Data? {
            requestCount += 1
            return nil
        }
    }
}
