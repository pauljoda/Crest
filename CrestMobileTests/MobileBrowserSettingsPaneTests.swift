import SwiftUI
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSettingsPaneTests: XCTestCase {

    func testAutomaticQuoteSubstitutionRetainsTheMobileDefault() throws {
        let suiteName = "crest.tests.webkit-text-input.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        BrowserAutomaticQuoteSubstitutionPreference.registerDefault(
            defaults: defaults
        )

        XCTAssertTrue(
            BrowserAutomaticQuoteSubstitutionPreference.defaultIsEnabled
        )
        XCTAssertTrue(
            defaults.bool(
                forKey: BrowserAutomaticQuoteSubstitutionPreference.key
            )
        )
    }

    /// The record row folds a permission's narrowing detail into its label, which is
    /// how three approved external-app schemes read as three rows rather than three
    /// identical ones.
    func testPermissionRowsDistinguishRecordsByTheirDetail() {
        let center = BrowserSitePermissionCenter()
        let spaceID = SpaceID()
        let origin = BrowserSiteOrigin(scheme: "https", host: "chat.example", port: 443)
        center.setDecision(
            .grantPersistently,
            for: .externalApplications,
            origin: origin,
            detail: "mailto",
            in: spaceID
        )
        center.setDecision(
            .denyPersistently,
            for: .externalApplications,
            origin: origin,
            detail: "tel",
            in: spaceID
        )

        let records = center.records(in: spaceID)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(
            Set(records.map(\.displayLabel)).count,
            2,
            "Two schemes on one capability must not present as one row twice."
        )
        for record in records {
            XCTAssertTrue(record.displayLabel.contains(record.detail ?? ""))
        }
    }

}
