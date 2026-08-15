import Foundation
import XCTest
@testable import Crest

final class BrowserOnboardingLegacyDraftCleanupTests: XCTestCase {
    func testLaunchCleanupDiscardsOnlyLegacyWizardDrafts() throws {
        let suite = "BrowserOnboardingLegacyDraftCleanupTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("import".utf8), forKey: BrowserOnboardingLegacyDraftCleanup.importDraftKey)
        defaults.set(
            Data("manual".utf8),
            forKey: BrowserOnboardingLegacyDraftCleanup.manualSetupDraftKey
        )
        defaults.set("preserved", forKey: "unrelated")

        BrowserOnboardingLegacyDraftCleanup.clear(defaults: defaults)

        XCTAssertNil(
            defaults.data(forKey: BrowserOnboardingLegacyDraftCleanup.importDraftKey)
        )
        XCTAssertNil(
            defaults.data(forKey: BrowserOnboardingLegacyDraftCleanup.manualSetupDraftKey)
        )
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "preserved")
    }
}
