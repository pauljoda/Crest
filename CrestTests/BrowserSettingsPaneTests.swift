import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPaneTests: XCTestCase {

    // MARK: - Panes

    /// The three panes moved out of the macOS shell in A4a are shared source. This
    /// asserts they still resolve against a real store on this platform — the cheap
    /// half of "compiles and composes on both platforms"; `CrestMobileTests` holds
    /// the other half.
    func testEverySharedSettingsPaneComposesAgainstAStore() {
        let browser = BrowserStore.preview()
        let pages = BrowserPagePool()
        let spaceAccess = BrowserSpaceAccessController()

        XCTAssertNotNil(
            BrowserLinkSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess
            ).body
        )
        XCTAssertNotNil(
            BrowserExtensionSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                extensionControllerPool: pages.extensionControllerPool
            ).body
        )
        XCTAssertNotNil(
            BrowserAdvancedSettingsPane(
                browser: browser,
                spaceAccess: spaceAccess,
                setupActions: [],
                showsMacOSImportRequirement: false
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
                layout: .macOSPage,
                searchText: .constant("")
            ).body
        )
    }

    /// The Setup section is data because the two shells offer different setup
    /// capabilities, so a caller's action has to survive the trip into the pane.
    func testAdvancedSetupActionCarriesItsIdentityAndFires() {
        var fired = 0
        let action = BrowserAdvancedSetupAction(
            id: "manual-setup",
            title: "Review & Customize Setup…",
            symbol: "sparkles",
            help: "Edit current Spaces or add Spaces and tabs in the setup preview",
            identifier: "mobile-open-setup"
        ) {
            fired += 1
        }

        XCTAssertEqual(action.id, "manual-setup")
        XCTAssertEqual(action.symbol, "sparkles")
        XCTAssertNotNil(action.help)
        XCTAssertEqual(action.identifier, "mobile-open-setup")
        action.action()
        XCTAssertEqual(fired, 1)
    }

    // MARK: - Pane header

    /// `settings-page-header` (macOS) and `settings-header-<rawValue>` (iOS) are the
    /// identifiers the automation suites read, and unifying the header must not
    /// rename either one.
    func testPaneHeaderKeepsEachShellsIdentifierContract() {
        for destination in BrowserSettingsDestination.allCases {
            let header = BrowserSettingsPaneHeader(
                destination: destination,
                identifier: "settings-header-\(destination.rawValue)",
                layout: .mobilePage
            )
            XCTAssertEqual(
                header.identifier,
                "settings-header-\(destination.rawValue)"
            )
            XCTAssertNotNil(header.body)
        }

        let page = BrowserSettingsPaneHeader(
            destination: .general,
            identifier: "settings-page-header",
            layout: .macOSPage
        )
        XCTAssertEqual(page.identifier, "settings-page-header")
    }

    /// The desktop window is measured in points against a fixed compact titlebar, so
    /// its tile stays put; the iOS sheet is read at the reader's own text size.
    func testOnlyTheMobileHeaderFollowsDynamicTypeForItsTile() {
        XCTAssertFalse(
            BrowserSettingsPaneHeaderLayout.macOSPage.scalesIconWithDynamicType
        )
        XCTAssertTrue(
            BrowserSettingsPaneHeaderLayout.mobilePage.scalesIconWithDynamicType
        )
    }

    /// The macOS header inherits the page-icon size the settings policy already
    /// pinned, and iOS keeps the tile metrics it has shipped, so neither surface
    /// shifts under a reader when the drawing is unified.
    func testPaneHeaderLayoutsKeepTheirShippedMetrics() {
        let mac = BrowserSettingsPaneHeaderLayout.macOSPage
        XCTAssertEqual(mac.iconSize, BrowserSettingsVisualPolicy.pageIconSize)
        XCTAssertEqual(mac.symbolSize, 21)
        XCTAssertEqual(mac.cornerRadius, CrestRadius.control)
        XCTAssertEqual(mac.iconSpacing, CrestSpacing.small)
        XCTAssertEqual(mac.horizontalPadding, CrestSpacing.section)
        XCTAssertEqual(mac.topPadding, CrestSpacing.extraExtraLarge)
        XCTAssertEqual(mac.bottomPadding, CrestSpacing.extraLarge)

        let mobile = BrowserSettingsPaneHeaderLayout.mobilePage
        XCTAssertEqual(mobile.iconSize, 58)
        XCTAssertEqual(mobile.symbolSize, 25)
        XCTAssertEqual(mobile.cornerRadius, 15)
        XCTAssertEqual(mobile.iconSpacing, CrestSpacing.medium)
        XCTAssertEqual(mobile.horizontalPadding, 28)
        XCTAssertEqual(mobile.topPadding, CrestSpacing.large)
        XCTAssertEqual(mobile.bottomPadding, CrestSpacing.large)

        XCTAssertEqual(
            BrowserSettingsPaneHeader.subtitleSpacing,
            CrestSpacing.extraSmall
        )
    }

    /// The header is the moment the brand identity reaches Settings: the destination
    /// hue it draws is the same hue its sidebar row and its selection wear.
    func testPaneHeaderDrawsTheDestinationsOwnBrandHue() {
        XCTAssertFalse(BrowserSettingsVisualPolicy.usesMonochromePageIdentity)
        XCTAssertTrue(BrowserSettingsVisualPolicy.usesEditorialPageIdentity)
        XCTAssertTrue(BrowserSettingsVisualPolicy.usesBrandSelectionTint)

        for destination in BrowserSettingsDestination.allCases {
            XCTAssertNotEqual(
                destination.color,
                Color.accentColor,
                "\(destination.rawValue) must stand for a fixed brand hue."
            )
        }
    }

    // MARK: - Extension status

    /// Both shells used to derive an extension's colour by switching on its English
    /// status *string*. The condition decides once, and the label and colour both
    /// read from the decision.
    func testExtensionStatusFollowsTheConditionRatherThanItsLabel() {
        XCTAssertEqual(
            BrowserExtensionStatus(summary(isEnabled: false, isLoaded: true)),
            .off
        )
        XCTAssertEqual(
            BrowserExtensionStatus(
                summary(isEnabled: false, isLoaded: false, errors: ["broken"])
            ),
            .off,
            "A disabled extension reports being off before it reports a problem."
        )
        XCTAssertEqual(
            BrowserExtensionStatus(summary(isEnabled: true, isLoaded: false)),
            .needsAttention
        )
        XCTAssertEqual(
            BrowserExtensionStatus(
                summary(isEnabled: true, isLoaded: true, errors: ["broken"])
            ),
            .needsAttention
        )
        XCTAssertEqual(
            BrowserExtensionStatus(summary(isEnabled: true, isLoaded: true)),
            .on
        )
        XCTAssertEqual(
            BrowserExtensionStatus(
                summary(
                    isEnabled: true,
                    isLoaded: false,
                    compatibilityAssessment:
                        BrowserExtensionCompatibilityPolicy.assess(
                            requestedPermissions: ["nativeMessaging"],
                            source: .unpackedPackage,
                            nativeMessagingCapability: .available
                        )
                )
            ),
            .needsAttention
        )

        XCTAssertEqual(BrowserExtensionStatus.on.color, .green)
        XCTAssertEqual(BrowserExtensionStatus.off.color, .secondary)
        XCTAssertEqual(BrowserExtensionStatus.needsAttention.color, .orange)
    }

    // MARK: - Passwords

    /// The two shells split the Passwords pane along different lines and both splits
    /// shipped: the desktop lists a Space's passwords on the page and exports from
    /// there, while touch keeps that list in a sheet and puts the Space's credential
    /// preferences on the page instead. Sharing the pane must not quietly move
    /// either half.
    func testPasswordPaneLayoutsKeepEachShellsShippedShape() {
        let mac = BrowserPasswordSettingsLayout.macOSPage
        XCTAssertTrue(mac.showsSavedPasswords)
        XCTAssertTrue(mac.showsExportAction)
        XCTAssertFalse(mac.showsManageAction)
        XCTAssertFalse(
            mac.showsCredentialPreferences,
            "The desktop edits a Space's password preferences in the Spaces pane."
        )

        let mobile = BrowserPasswordSettingsLayout.mobilePage
        XCTAssertTrue(mobile.showsCredentialPreferences)
        XCTAssertTrue(mobile.showsManageAction)
        XCTAssertFalse(mobile.showsSavedPasswords)
        XCTAssertFalse(
            mobile.showsExportAction,
            "Touch exports from inside the sheet that owns the list."
        )

        XCTAssertNotEqual(mac, mobile)
    }

    /// The pane's search runs over four fields, and both shells had written their own
    /// copy of the predicate.
    func testCredentialSearchMatchesAccountSiteLabelAndScope() {
        let spaceID = SpaceID()
        let origin = CredentialOrigin(url: URL(string: "https://mail.example")!)!
        let other = CredentialOrigin(url: URL(string: "https://intranet.example")!)!
        let webForm = CredentialDescriptor(
            spaceID: spaceID,
            origin: origin,
            username: "person@example.com",
            displayName: "Work mail"
        )
        let httpBasic = CredentialDescriptor(
            spaceID: spaceID,
            origin: other,
            scope: .httpBasic(realm: "Members"),
            username: "operator"
        )
        let all = [webForm, httpBasic]

        XCTAssertEqual(
            BrowserCredentialSettingsPolicy.filter(all, matching: "  "),
            all,
            "A blank query is not a filter."
        )
        XCTAssertEqual(
            BrowserCredentialSettingsPolicy.filter(all, matching: "PERSON"),
            [webForm]
        )
        XCTAssertEqual(
            BrowserCredentialSettingsPolicy.filter(all, matching: "work mail"),
            [webForm]
        )
        XCTAssertEqual(
            BrowserCredentialSettingsPolicy.filter(all, matching: "intranet"),
            [httpBasic]
        )
        XCTAssertEqual(
            BrowserCredentialSettingsPolicy.filter(all, matching: "Realm"),
            [httpBasic],
            "The authentication scope is part of how a reader finds a credential."
        )
    }

    /// Deletion is irreversible and can reach past this device, so the confirmation
    /// names the account, the site, the scope, the Space, and the synchronized copy.
    func testDeletionMessageNamesTheScopeAndTheSynchronizedCopy() {
        let spaceID = SpaceID()
        let origin = CredentialOrigin(url: URL(string: "https://intranet.example")!)!
        let synchronized = CredentialDescriptor(
            spaceID: spaceID,
            origin: origin,
            scope: .httpBasic(realm: "Members"),
            username: "operator",
            isSynchronizable: true
        )
        let local = CredentialDescriptor(
            spaceID: spaceID,
            origin: origin,
            username: "operator"
        )

        let synchronizedMessage = BrowserCredentialSettingsPolicy.deletionMessage(
            for: synchronized,
            spaceName: "Work"
        )
        XCTAssertTrue(synchronizedMessage.contains("operator"))
        XCTAssertTrue(synchronizedMessage.contains("intranet.example"))
        XCTAssertTrue(synchronizedMessage.contains("Realm"))
        XCTAssertTrue(synchronizedMessage.contains("from Work?"))
        XCTAssertTrue(synchronizedMessage.contains("iCloud Keychain item"))
        XCTAssertTrue(synchronizedMessage.hasSuffix("This cannot be undone."))

        let localMessage = BrowserCredentialSettingsPolicy.deletionMessage(
            for: local,
            spaceName: "Work"
        )
        XCTAssertFalse(
            localMessage.contains("iCloud"),
            "A local-only password must not claim to remove a synchronized copy."
        )
        XCTAssertFalse(localMessage.contains("("), "A web form has no scope to name.")
    }

    /// An empty list means two different things, and says so.
    func testEmptyPasswordDescriptionDependsOnWhetherAQueryIsRunning() {
        XCTAssertNotEqual(
            BrowserCredentialSettingsPolicy.emptyDescription(isSearching: true),
            BrowserCredentialSettingsPolicy.emptyDescription(isSearching: false)
        )
        XCTAssertTrue(
            BrowserCredentialSettingsPolicy
                .emptyDescription(isSearching: false)
                .contains("only in this Space")
        )
    }

    // MARK: - Shared bindings

    /// Eight panes had each written this rule out privately. A selection survives as
    /// long as its Space does, and otherwise falls back to the selected Space.
    func testSpaceSelectionSurvivesUntilItsSpaceDoes() {
        let browser = BrowserStore.preview()
        let existing = browser.session.spaces[1].id

        XCTAssertEqual(browser.repairedSpaceSelection(existing), existing)
        XCTAssertEqual(
            browser.repairedSpaceSelection(nil),
            browser.session.selectedSpaceID
        )
        XCTAssertEqual(
            browser.repairedSpaceSelection(SpaceID()),
            browser.session.selectedSpaceID,
            "A Space deleted out from under a pane hands the pane back the live one."
        )
    }

    /// Every shared binding writes through to the session rather than to the copy of
    /// the Space the view happens to be holding — which is what the drifted private
    /// copies did not all do.
    func testSharedSpaceBindingsWriteThroughToTheLiveSession() {
        let browser = BrowserStore.preview()
        let space = browser.session.spaces[0]

        let name = browser.spaceIdentityBinding(\.name, in: space)
        name.wrappedValue = "Renamed"
        XCTAssertEqual(browser.session.space(id: space.id)?.name, "Renamed")
        XCTAssertEqual(name.wrappedValue, "Renamed")

        let provider = browser.browsingPreferenceBinding(\.searchProvider, in: space)
        let otherProvider = BrowserSearchProvider.allCases.first {
            $0 != provider.wrappedValue
        }!
        provider.wrappedValue = otherProvider
        XCTAssertEqual(
            browser.session.space(id: space.id)?.browsingPreferences.searchProvider,
            otherProvider
        )

        let offersCopy = browser.credentialPreferenceBinding(
            \.alsoOffersSaveToSystemPasswords,
            in: space
        )
        offersCopy.wrappedValue = !offersCopy.wrappedValue
        XCTAssertEqual(
            browser.session.space(id: space.id)?.credentialPreferences
                .alsoOffersSaveToSystemPasswords,
            offersCopy.wrappedValue
        )

        let managerEnabled = browser.credentialPreferenceBinding(
            \.isEnabled,
            in: space
        )
        managerEnabled.wrappedValue = false
        XCTAssertFalse(
            browser.session.space(id: space.id)?.credentialPreferences.isEnabled
                ?? true
        )

        let defaultSpace = browser.defaultSpaceBinding()
        defaultSpace.wrappedValue = browser.session.spaces[1].id
        XCTAssertEqual(browser.session.defaultSpaceID, browser.session.spaces[1].id)
        XCTAssertEqual(defaultSpace.wrappedValue, browser.session.spaces[1].id)
    }

    /// Privacy resolves its content-blocking policy before it is sure it has a Space,
    /// so the identifier-addressed binding has to answer with the default rather than
    /// crash or write into nothing.
    func testContentBlockingBindingToleratesAPaneWithoutASpaceYet() {
        let browser = BrowserStore.preview()
        let spaceID = browser.session.spaces[0].id

        let missing = browser.browsingPreferenceBinding(
            \.contentBlockingPolicy,
            in: SpaceID?.none,
            default: .balanced
        )
        XCTAssertEqual(missing.wrappedValue, .balanced)
        missing.wrappedValue = .off

        let live = browser.browsingPreferenceBinding(
            \.contentBlockingPolicy,
            in: Optional(spaceID),
            default: .balanced
        )
        live.wrappedValue = .off
        XCTAssertEqual(
            browser.session.space(id: spaceID)?.browsingPreferences
                .contentBlockingPolicy,
            .off
        )
    }

    // MARK: - Default browser

    /// The desktop claims the HTTP handlers itself; iOS can only open Default Apps
    /// Settings. General reads that from the controller rather than from `#if os`, so
    /// the pane's one platform seam is a value a test can set.
    func testGeneralPaneReadsItsDefaultBrowserSeamFromTheRequestStyle() {
        XCTAssertEqual(
            BrowserDefaultBrowserController().requestStyle,
            .direct,
            "macOS sets the default browser without leaving Crest."
        )
        XCTAssertEqual(
            BrowserDefaultBrowserController(requestStyle: .systemSettings)
                .requestStyle,
            .systemSettings
        )
    }

    private func summary(
        isEnabled: Bool,
        isLoaded: Bool,
        errors: [String] = [],
        compatibilityAssessment: BrowserExtensionCompatibilityAssessment =
            .compatible
    ) -> BrowserExtensionSummary {
        BrowserExtensionSummary(
            id: "extension",
            displayName: "Extension",
            version: "1.0",
            requestedPermissions: [],
            requestedHosts: [],
            unsupportedAPIs: [],
            errors: errors,
            isEnabled: isEnabled,
            isLoaded: isLoaded,
            permissionSnapshot: BrowserExtensionPermissionSnapshot(),
            compatibilityAssessment: compatibilityAssessment
        )
    }
}
