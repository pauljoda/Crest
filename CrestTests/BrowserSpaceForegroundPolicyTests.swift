import XCTest
@testable import Crest

final class BrowserSpaceForegroundPolicyTests: XCTestCase {
    func testDarkBrandingUsesLightForegroundContent() {
        let branding = BrowserSpaceBranding(
            colors: [.ink],
            readabilityFade: 0
        )

        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: branding),
            .light
        )
    }

    func testBrightBrandingUsesDarkForegroundWhenItHasBetterContrast() {
        let branding = BrowserSpaceBranding(
            colors: [.sand, .gold],
            readabilityFade: 0
        )

        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: branding),
            .dark
        )
    }

    func testMixedBrandingProtectsTheDarkestRegion() {
        let branding = BrowserSpaceBranding(
            colors: [.ink, .gold, .sand],
            readabilityFade: 0.45
        )

        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.tone(for: branding),
            .light
        )
    }

    func testDesignSystemMapsForegroundToneToTheMatchingSystemScheme() {
        let darkBranding = BrowserSpaceBranding(
            colors: [.ink],
            readabilityFade: 0
        )
        let brightBranding = BrowserSpaceBranding(
            colors: [.sand, .gold],
            readabilityFade: 0
        )

        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.colorScheme(for: darkBranding),
            .dark
        )
        XCTAssertEqual(
            BrowserSpaceForegroundPolicy.colorScheme(for: brightBranding),
            .light
        )
    }
}
