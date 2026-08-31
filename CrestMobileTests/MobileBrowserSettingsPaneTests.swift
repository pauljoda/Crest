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
        XCTAssertNotNil(BrowserAboutSettingsPane().body)
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

    func testMobileGeneralSettingsUsesTheSharedDefaultZoomSection() {
        let preferences = BrowserDefaultPageZoomStore(
            persistence: InMemoryBrowserDefaultPageZoomPersistence()
        )
        let section = BrowserDefaultPageZoomSettingsSection(
            preferences: preferences
        )

        XCTAssertEqual(preferences.defaultZoom, 1)
        XCTAssertEqual(
            BrowserDefaultPageZoomSettingsSection.controlIdentifier,
            "default-page-zoom-slider"
        )
        XCTAssertNotNil(section.body)
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
        XCTAssertTrue(
            BrowserSettingsDestination.platformCases.contains(.about),
            "Build information and support routes belong on every platform."
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

    func testMobileSettingsNeverOffersTheWebKitFeatureFlagsDestination() {
        XCTAssertFalse(
            BrowserPlatformSettingsDestinationCatalog.isAvailable(.featureFlags)
        )
        XCTAssertFalse(
            BrowserPlatformSettingsDestinationCatalog.cases.contains(.featureFlags)
        )
        XCTAssertFalse(
            BrowserSettingsDestination.featureFlags.isAvailableOnCurrentPlatform
        )
        XCTAssertFalse(
            BrowserSettingsDestination.platformCases.contains(.featureFlags),
            "WebKit's private feature registry is a macOS-only settings surface."
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

    /// Touch takes the Space settings superset by passing nothing extra, so the
    /// default capabilities have to be exactly the compact shell's list. A
    /// section that started rendering here because someone flipped a default
    /// would put a folder chooser on a device with nowhere to chase it to.
    func testDefaultSpaceSettingsCapabilitiesAreTheTouchSubset() {
        let capabilities = BrowserSpaceSettingsCapabilities()

        XCTAssertNil(capabilities.downloads)
        XCTAssertFalse(capabilities.editsCrestPasswords)
    }

    /// The superset is shared source, so every section the windowed shell asks
    /// for has to resolve in this target too — including the two that only it
    /// passes. This is what keeps the fork from growing back: a section that
    /// compiled only against AppKit would fail here rather than in review.
    func testSharedSpaceSettingsSectionsResolveForBothShellsSubsets() throws {
        let browser = BrowserStore.preview()
        let spaceAccess = BrowserSpaceAccessController()
        let dataDeleter = InertSpaceDataDeleter()
        let space = try XCTUnwrap(browser.session.spaces.first)

        XCTAssertNotNil(
            BrowserSpaceSettingsSections(
                browser: browser,
                space: space,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter
            ).body
        )

        var asksWhereToSave = false
        let windowed = BrowserSpaceSettingsCapabilities(
            downloads: BrowserSpaceDownloadSettings(
                asksWhereToSave: Binding(
                    get: { asksWhereToSave },
                    set: { asksWhereToSave = $0 }
                ),
                directoryName: "Downloads",
                usesCustomDirectory: false,
                errorMessage: nil,
                explanation: "Downloads land here.",
                chooseDirectory: {},
                resetDirectory: {}
            ),
            editsCrestPasswords: true
        )

        XCTAssertNotNil(windowed.downloads)
        XCTAssertTrue(windowed.editsCrestPasswords)
        XCTAssertNotNil(
            BrowserSpaceSettingsSections(
                browser: browser,
                space: space,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                capabilities: windowed
            ).body
        )
    }

    /// Each section the superset composes has to stand on its own, because the
    /// shells reach for them individually as their panes grow.
    func testEverySharedSpaceSettingsSectionComposesAgainstAStore() throws {
        let browser = BrowserStore.preview()
        let spaceAccess = BrowserSpaceAccessController()
        let space = try XCTUnwrap(browser.session.spaces.first)

        XCTAssertNotNil(
            BrowserSpaceBrowsingSection(browser: browser, space: space).body
        )
        XCTAssertNotNil(
            BrowserSpaceAccessPolicySection(
                browser: browser,
                space: space,
                spaceAccess: spaceAccess
            ).body
        )
        XCTAssertNotNil(
            BrowserSpaceCredentialSyncSection(
                browser: browser,
                space: space
            ).body
        )
    }

    /// A section inside the mobile Form is not a stable sheet presenter. The
    /// Space page owns that presentation and the shared section delegates the
    /// request to it; desktop can continue using the section's local default.
    func testMobileSearchEngineManagementDelegatesToTheSpacePage() throws {
        let browser = BrowserStore.preview()
        let space = try XCTUnwrap(browser.session.spaces.first)
        var requestedManagement = false
        let section = BrowserSpaceBrowsingSection(
            browser: browser,
            space: space,
            manageSearchEngines: {
                requestedManagement = true
            }
        )

        section.requestSearchEngineManagement()

        XCTAssertTrue(requestedManagement)
    }

    /// A sheet presented from the mobile manager replaces its containing sheet
    /// on iPhone. The manager already owns a NavigationStack, so touch edits use
    /// that stable route while macOS keeps its windowed sheet presentation.
    func testMobileSearchEngineEditorUsesManagerNavigation() {
        XCTAssertEqual(
            BrowserSearchEngineEditorPresentationStyle.platformDefault,
            .navigation
        )
        XCTAssertEqual(
            BrowserSearchEngineEditorKeyboardDismissalStyle.platformDefault,
            .resignFirstResponder
        )
        XCTAssertTrue(
            BrowserSearchEngineEditorKeyboardDismissalStyle.platformDefault
                .repeatsDismissalAfterNavigation
        )
    }

    /// Provider artwork in a touch picker needs its own readable slot. The
    /// compact desktop label remains smaller, but mobile gives the mark a clear
    /// gap from the title and enough vertical breathing room to stay centered.
    func testMobileSearchProviderLabelsUseRoomyTouchMetrics() {
        let layout = BrowserSearchProviderIdentityLabelLayout.platformDefault

        XCTAssertEqual(layout, .touch)
        XCTAssertEqual(layout.iconSize, 28)
        XCTAssertEqual(layout.spacing, 8)
        XCTAssertEqual(layout.verticalPadding, 4)
    }

    /// A native menu Picker flattens the selected provider's composed label on
    /// iOS, collapsing the artwork, title, and disclosure indicator together.
    /// Touch settings use an explicitly laid-out menu value for both browsing
    /// dropdowns so their trailing values stay aligned and comfortably spaced.
    func testMobileBrowsingDropdownsUsePaddedMenuValueLabels() {
        XCTAssertEqual(
            BrowserSpaceBrowsingPickerPresentationStyle.platformDefault,
            .paddedMenu
        )
        XCTAssertTrue(
            BrowserSpaceBrowsingPickerPresentationStyle.platformDefault
                .dismissesKeyboardAfterSelection
        )

        let layout = BrowserSpaceBrowsingPickerValueLayout.touch
        XCTAssertEqual(layout.minimumLeadingGap, 16)
        XCTAssertEqual(layout.providerTextSpacing, 10)
        XCTAssertEqual(layout.disclosureSpacing, 8)
        XCTAssertEqual(layout.verticalPadding, 5)
        XCTAssertEqual(layout.providerTitleLineLimit, 1)
        XCTAssertEqual(layout.minimumProviderTitleScale, 0.8)
    }
}

/// A deleter for composition checks, which never reach the delete button.
@MainActor
private final class InertSpaceDataDeleter: BrowserSpaceDataDeleting {
    func deleteData(for space: BrowserSpace) async throws {}
}
