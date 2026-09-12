import SwiftUI
import XCTest

@testable import Crest

@MainActor
final class BrowserSettingsPaneTests: XCTestCase {

    func testBundledDockPluginCanLoadItsDeclaredPrincipalClass() throws {
        let name = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "NSDockTilePlugIn") as? String)
        let directory = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let plugin = try XCTUnwrap(Bundle(url: directory.appendingPathComponent(name)))
        try plugin.loadAndReturnError()
        XCTAssertNotNil(plugin.principalClass as? any NSDockTilePlugIn.Type)
    }

    func testMacWebTextAssistanceForcesEverySmartMutationOff() throws {
        let suiteName = "crest.tests.webkit-text-input.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expectedKeys = Set([
            "WebAutomaticSpellingCorrectionEnabled",
            "WebGrammarCheckingEnabled",
            "WebSmartInsertDeleteEnabled",
            "WebSmartListsEnabled",
            "WebAutomaticQuoteSubstitutionEnabled",
            "WebAutomaticDashSubstitutionEnabled",
            "WebAutomaticLinkDetectionEnabled",
            "WebAutomaticTextReplacementEnabled",
        ])
        for key in BrowserMacWebTextAssistancePolicy.disabledSmartTextKeys {
            defaults.set(true, forKey: key)
        }

        BrowserMacWebTextAssistancePolicy.configure(
            defaults: defaults
        )

        XCTAssertEqual(
            Set(BrowserMacWebTextAssistancePolicy.disabledSmartTextKeys),
            expectedKeys
        )
        XCTAssertEqual(
            BrowserMacWebTextAssistancePolicy.disabledSmartTextKeys.count,
            expectedKeys.count
        )
        for key in BrowserMacWebTextAssistancePolicy.disabledSmartTextKeys {
            XCTAssertFalse(defaults.bool(forKey: key), key)
        }
    }

    func testMacWebTextAssistanceDefaultsSpellCheckingOff() throws {
        let suiteName = "crest.tests.webkit-text-input.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        BrowserMacWebTextAssistancePolicy.configure(
            defaults: defaults
        )

        XCTAssertFalse(
            BrowserMacWebTextAssistancePolicy.defaultIsSpellCheckingEnabled
        )
        XCTAssertFalse(
            defaults.bool(forKey: BrowserMacWebTextAssistancePolicy.spellCheckingKey)
        )
    }

    func testMacWebTextAssistancePreservesAnExplicitSpellCheckingChoice() throws {
        let suiteName = "crest.tests.webkit-text-input.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            true,
            forKey: BrowserMacWebTextAssistancePolicy.spellCheckingKey
        )

        BrowserMacWebTextAssistancePolicy.configure(defaults: defaults)

        XCTAssertTrue(
            defaults.bool(forKey: BrowserMacWebTextAssistancePolicy.spellCheckingKey)
        )
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

    }

    // MARK: - Passwords

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
            [httpBasic, webForm],
            "A blank query keeps every password and orders the manager by site."
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
