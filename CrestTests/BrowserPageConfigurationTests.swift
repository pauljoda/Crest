import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserPageConfigurationTests: XCTestCase {
    func testProductionConfigurationUsesTheSpacesPersistentStoreAndDesktopBrowserDefaults() {
        let profile = UUID()

        let configuration = BrowserPageConfiguration.make(
            forProfile: profile,
            websiteDataStore: BrowserWebsiteDataStore.persistent(forProfile: profile)
        )

        XCTAssertEqual(configuration.websiteDataStore.identifier, profile)
        XCTAssertEqual(
            configuration.applicationNameForUserAgent,
            BrowserPlatformUserAgent.applicationName
        )
        XCTAssertEqual(configuration.defaultWebpagePreferences.preferredContentMode, .desktop)
        XCTAssertTrue(configuration.defaultWebpagePreferences.allowsContentJavaScript)
        XCTAssertTrue(configuration.allowsAirPlayForMediaPlayback)
        XCTAssertTrue(configuration.preferences.isElementFullscreenEnabled)
        XCTAssertFalse(
            configuration.preferences.javaScriptCanOpenWindowsAutomatically,
            "Automatic windows are blocked until the site has explicit permission; user-activated windows are unaffected by this WebKit setting."
        )
        XCTAssertEqual(configuration.preferences.inactiveSchedulingPolicy, .suspend)
        XCTAssertTrue(configuration.upgradeKnownHostsToHTTPS)
        XCTAssertFalse(configuration.suppressesIncrementalRendering)
        XCTAssertFalse(configuration.limitsNavigationsToAppBoundDomains)
    }

}
