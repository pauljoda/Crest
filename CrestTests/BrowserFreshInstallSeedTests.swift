import XCTest
@testable import Crest

final class BrowserFreshInstallSeedTests: XCTestCase {
    func testFreshInstallStartsWithOneDisposablePersonalSpace() throws {
        let session = BrowserSession.freshInstallSeed
        let space = try XCTUnwrap(session.spaces.first)

        XCTAssertEqual(session.spaces.count, 1)
        XCTAssertEqual(session.selectedSpaceID, space.id)
        XCTAssertEqual(space.name, "Personal")
        XCTAssertEqual(space.tabs.count, 1)
        XCTAssertEqual(space.selectedTabID, space.tabs.first?.id)
        XCTAssertTrue(try XCTUnwrap(space.tabs.first).isStartPage)
        XCTAssertTrue(space.pinnedTabs.isEmpty)
        XCTAssertTrue(space.savedTabs.isEmpty)
        XCTAssertNotNil(session.disposableSeedMarker)
    }

    func testFreshInstallSeedWearsTheWinterHousePalette() throws {
        let space = try XCTUnwrap(BrowserSession.freshInstallSeed.spaces.first)

        XCTAssertEqual(space.branding.colors, BrowserSpaceHousePalette.winter.colors)
        XCTAssertEqual(
            space.branding.readabilityFade,
            BrowserSpaceBranding.initialReadabilityFade
        )
        XCTAssertEqual(space.branding.bannerPattern, .diagonal)
        XCTAssertEqual(space.branding.bannerStrength, 1)
        XCTAssertEqual(space.branding.iconStyle, .simpleSymbol)
        XCTAssertEqual(space.branding.crest.symbol, .mountain)
        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: space.branding),
            .light
        )
        // The seeded Space is one of the nine, so the swatch row opens already
        // showing the reader which palette they are looking at.
        XCTAssertEqual(
            BrowserSpaceBrandingPreset.curated.first {
                $0.isSelected(in: space.branding)
            }?.title,
            "Winter"
        )
    }
}
