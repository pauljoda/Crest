import SwiftUI
import XCTest

@testable import CrestMobile

@MainActor
final class MobileBrowserSettingsPaneTests: XCTestCase {

    /// Compact-width Forms must not ask `ViewThatFits` to choose again while the
    /// Space name field updates the preview. UIKit reports that feedback loop as
    /// a collection-view layout crash during renaming.
    func testSpaceCustomizationKeepsCompactWidthsOnTheStableVerticalLayout() {
        XCTAssertTrue(
            MobileSpaceCustomizationSection.usesStableCompactLayout(for: .compact)
        )
        XCTAssertTrue(
            MobileSpaceCustomizationSection.usesStableCompactLayout(for: nil)
        )
        XCTAssertFalse(
            MobileSpaceCustomizationSection.usesStableCompactLayout(for: .regular)
        )
    }

    /// The other half of A4a's "one pane, both shells": the panes extracted from the
    /// two settings views are shared source, so each one has to resolve on iOS too —
    /// where the same body carries the pane header as the form's first row.
    func testEverySharedSettingsPaneComposesAgainstAStore() {
        let browser = BrowserStore.preview()
        let pages = MobileBrowserPageStore()
        let spaceAccess = BrowserSpaceAccessController()

        XCTAssertNotNil(
            BrowserLinkSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess
            ).body
        )
        XCTAssertNotNil(
            BrowserAdvancedSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                setupActions: [
                    .init(
                        id: "replay-setup",
                        title: "Review Crest Setup",
                        symbol: "sparkles",
                        identifier: "mobile-open-setup"
                    ) {}
                ],
                showsMacOSImportRequirement: true
            ).body
        )
        XCTAssertNotNil(
            BrowserSyncSettingsView(
                browser: browser,
                cloudSync: BrowserCloudSyncController(
                    browser: browser,
                    configuration: nil
                )
            ).body
        )
        XCTAssertNotNil(BrowserGeneralSettingsPane(browser: browser).body)
        XCTAssertNotNil(
            BrowserPrivacySettingsPane(
                browser: browser,
                downloadCenter: pages.downloadCenter,
                spaceAccess: spaceAccess,
                permissionCenter: pages.permissionCenter,
                contentBlockingErrorDescription: nil
            ).body
        )
        XCTAssertNotNil(
            BrowserPasswordSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                layout: .mobilePage,
                manage: {}
            ).body
        )
        XCTAssertNotNil(
            MobilePasswordSettingsView(
                browser: browser,
                spaceAccess: spaceAccess
            ).body
        )
    }

    /// Touch reaches the saved-password manager through a sheet, so the pane on the
    /// page shows the Space's preferences and a way in — never the list itself.
    func testMobilePasswordPaneKeepsTheManagerBehindASheet() {
        let layout = BrowserPasswordSettingsLayout.mobilePage

        XCTAssertTrue(layout.showsCredentialPreferences)
        XCTAssertTrue(layout.showsManageAction)
        XCTAssertFalse(layout.showsSavedPasswords)
        XCTAssertFalse(layout.showsExportAction)
    }

    /// iOS can only ask the system to change the default browser, so General offers
    /// Default Apps Settings rather than a direct claim. The pane branches on this
    /// value, not on the platform.
    func testMobileDefaultBrowserIsChangedThroughSystemSettings() {
        XCTAssertEqual(
            BrowserDefaultBrowserController().requestStyle,
            .systemSettings
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
            XCTAssertNotNil(
                BrowserSitePermissionRecordRow(
                    record: record,
                    permissionCenter: center
                ).body
            )
        }
    }

    /// iOS derives one identifier per destination for both the header row and the
    /// form around it, and `MobileAdaptiveUITests` drives settings by those names.
    func testMobilePaneWrapperKeepsThePerDestinationIdentifiers() {
        for destination in BrowserSettingsDestination.platformCases {
            let pane = BrowserSettingsPane(destination) {
                EmptyView()
            }
            XCTAssertEqual(pane.destination, destination)
            XCTAssertNotNil(pane.body)

            let header = BrowserSettingsPaneHeader(
                destination: destination,
                identifier: "settings-header-\(destination.rawValue)",
                layout: .mobilePage
            )
            XCTAssertEqual(
                header.identifier,
                "settings-header-\(destination.rawValue)"
            )
        }

        XCTAssertFalse(
            BrowserSettingsDestination.platformCases.contains(.shortcuts),
            "iOS has no rebindable command table, so it never builds that pane."
        )
    }

    /// Browser extensions are a macOS-only feature. The destination stays in the
    /// shared catalog for the desktop shell, and mobile must never offer a row
    /// for it: there is no mobile WebExtension runtime behind it to reach.
    func testMobileSettingsNeverOffersTheExtensionsDestination() {
        XCTAssertFalse(
            BrowserPlatformSettingsDestinationCatalog.isAvailable(.extensions)
        )
        XCTAssertFalse(
            BrowserPlatformSettingsDestinationCatalog.cases.contains(.extensions)
        )
        XCTAssertFalse(
            BrowserSettingsDestination.extensions.isAvailableOnCurrentPlatform
        )
        XCTAssertFalse(
            BrowserSettingsDestination.platformCases.contains(.extensions),
            "Extensions are macOS-only, so iOS never lists that row."
        )
    }

    /// The tile grows with the reader's text size on touch. macOS does not; the
    /// desktop half of this pair lives in `BrowserSettingsPaneTests`.
    func testMobileHeaderTileFollowsDynamicType() {
        XCTAssertTrue(
            BrowserSettingsPaneHeaderLayout.mobilePage.scalesIconWithDynamicType
        )
        XCTAssertEqual(BrowserSettingsPaneHeaderLayout.mobilePage.iconSize, 58)
        XCTAssertEqual(BrowserSettingsPaneHeaderLayout.mobilePage.symbolSize, 25)
    }

    /// The mobile settings sidebar washes its selected row with `Color.accentColor`,
    /// which iOS reads from the asset catalog. A4a left that wash alone rather than
    /// giving mobile a destination-coloured selection, and the reason it is already
    /// right is that the catalog accent *is* the brand coral. If the two ever drift,
    /// mobile selection silently stops being a brand decision.
    ///
    /// `Color.accentColor` cannot be resolved in a synthetic `EnvironmentValues`
    /// (it falls back to the system accent there), so the guard reads the catalog
    /// entry itself under each appearance.
    func testMobileSelectionWashUsesTheBrandAccent() throws {
        for colorScheme in [ColorScheme.light, .dark] {
            let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
            let traits = UITraitCollection(userInterfaceStyle: style)
            let catalogColor = try XCTUnwrap(
                UIColor(named: "AccentColor", in: .main, compatibleWith: traits),
                "The AccentColor asset must ship in the app bundle."
            )
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            var alpha: CGFloat = 0
            catalogColor.resolvedColor(with: traits)
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)

            var environment = EnvironmentValues()
            environment.colorScheme = colorScheme
            let brand = CrestBrandTheme.accent(colorScheme).resolve(in: environment)
            XCTAssertEqual(Double(red), Double(brand.red), accuracy: 0.01)
            XCTAssertEqual(Double(green), Double(brand.green), accuracy: 0.01)
            XCTAssertEqual(Double(blue), Double(brand.blue), accuracy: 0.01)
        }
    }
}
