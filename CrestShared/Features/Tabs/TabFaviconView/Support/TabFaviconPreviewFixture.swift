import Foundation
import SwiftUI

enum TabFaviconPreviewFixture {
    static let profileID = UUID(
        uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x70)
    )
    static let imageData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x04, 0x00, 0x00, 0x00, 0xB5, 0x1C, 0x0C,
        0x02, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41,
        0x54, 0x78, 0xDA, 0x63, 0x64, 0xF8, 0x0F, 0x00,
        0x01, 0x05, 0x01, 0x01, 0x27, 0x18, 0xE3, 0x66,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
    ])
    static let startPage = BrowserTab.startPage(
        id: tabID(0x10),
        lastActivatedAt: .distantPast
    )
    static let emoji = BrowserTab(
        id: tabID(0x20),
        title: "Research",
        url: URL(fileURLWithPath: "/preview/research"),
        symbol: BrowserTab.symbol(forEmoji: "🧭"),
        iconMode: .emoji,
        placement: .current,
        lastActivatedAt: .distantPast
    )
    static let image = BrowserTab(
        id: tabID(0x30),
        title: "Crest",
        url: URL(fileURLWithPath: "/preview/crest"),
        faviconData: imageData,
        placement: .current,
        lastActivatedAt: .distantPast
    )
    static let fallback = BrowserTab(
        id: tabID(0x40),
        title: "No Favicon",
        url: URL(fileURLWithPath: "/preview/no-favicon"),
        placement: .current,
        lastActivatedAt: .distantPast
    )

    static func renderedImage(
        for identity: BrowserFaviconTaskIdentity,
        maximumPixelSize: Int
    ) -> BrowserFaviconRenderedImage? {
        guard
            let decoded = BrowserFaviconImageDecoder.decodeSynchronously(
                imageData,
                maximumPixelSize: maximumPixelSize
            )
        else { return nil }
        return BrowserFaviconRenderedImage(
            requestIdentity: identity,
            image: Image(
                decorative: decoded,
                scale: TabFaviconMetrics.renderedImageScale
            )
        )
    }

    private static func tabID(_ tail: UInt8) -> TabID {
        TabID(
            rawValue: UUID(
                uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, tail)
            )
        )
    }
}
