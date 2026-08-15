import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionsPresentationTests: XCTestCase {
    func testRunningExtensionDetailUsesSingularCounts() {
        let summary = makeSummary(
            requestedPermissions: ["tabs"],
            requestedHosts: ["https://example.com/*"],
            isEnabled: true,
            isLoaded: true
        )

        XCTAssertEqual(
            BrowserExtensionSummaryPresentation.detailText(for: summary),
            "Running · 1 permission · 1 site rule"
        )
    }

    func testDisabledExtensionDetailUsesPluralCounts() {
        let summary = makeSummary(
            requestedPermissions: ["tabs", "storage"],
            requestedHosts: [],
            isEnabled: false,
            isLoaded: false
        )

        XCTAssertEqual(
            BrowserExtensionSummaryPresentation.detailText(for: summary),
            "Off · 2 permissions · 0 site rules"
        )
    }

    func testLoadedExtensionWithCompatibilityErrorNeedsAttention() {
        let summary = makeSummary(
            requestedPermissions: ["nativeMessaging"],
            requestedHosts: [],
            isEnabled: true,
            isLoaded: true,
            errors: ["Native messaging is unavailable."]
        )

        XCTAssertEqual(
            BrowserExtensionSummaryPresentation.detailText(for: summary),
            "Needs attention · 1 permission · 0 site rules"
        )
    }

    func testRuntimeFailureIsExplainedWithoutLeadingWithJavaScript() {
        let summary = makeSummary(
            requestedPermissions: ["storage"],
            requestedHosts: [],
            isEnabled: true,
            isLoaded: true,
            errors: [
                "TypeError: undefined is not an object "
                    + "(evaluating 'trie.regexps') (background/index.js:684:29)"
            ]
        )

        let issue = BrowserExtensionSummaryPresentation.issue(for: summary)

        XCTAssertEqual(issue?.title, "This extension ran into a problem")
        XCTAssertEqual(
            issue?.message,
            "Some features may not work correctly. Try turning the extension "
                + "off and back on. If the problem continues, update or "
                + "reinstall it."
        )
        XCTAssertEqual(issue?.technicalDetails, summary.errors)
        XCTAssertFalse(issue?.message.contains("TypeError") == true)
    }

    func testBlockingCompatibilityFailureExplainsWhyExtensionCannotRun() {
        let compatibilityMessage = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging"],
            source: .chromeWebStore,
            nativeMessagingCapability: .unavailableInAppSandbox
        ).blockingIssues[0].message
        let summary = makeSummary(
            requestedPermissions: ["nativeMessaging"],
            requestedHosts: [],
            isEnabled: true,
            isLoaded: false,
            compatibilityAssessment:
                BrowserExtensionCompatibilityPolicy
                .assess(
                    requestedPermissions: ["nativeMessaging"],
                    source: .chromeWebStore,
                    nativeMessagingCapability: .unavailableInAppSandbox
                )
        )

        let issue = BrowserExtensionSummaryPresentation.issue(for: summary)

        XCTAssertEqual(issue?.title, "This extension can’t run in Crest")
        XCTAssertEqual(issue?.message, compatibilityMessage)
        XCTAssertEqual(issue?.technicalDetails, [])
    }

    func test1PasswordSafariFailureExplainsTheActualUserImpact() {
        let summary = BrowserExtensionSummary(
            id: "com.1password.safari.extension",
            displayName: "1Password",
            version: "8.12.29.1",
            requestedPermissions: ["nativeMessaging"],
            requestedHosts: ["<all_urls>"],
            unsupportedAPIs: [],
            errors: ["[Browser] (background/background.js:35:15906)"],
            isEnabled: true,
            isLoaded: true,
            permissionSnapshot: .empty,
            sourceDisplayName: "1Password for Safari"
        )

        let issue = BrowserExtensionSummaryPresentation.issue(for: summary)

        XCTAssertEqual(
            issue?.title,
            "1Password can’t connect to its companion app"
        )
        XCTAssertEqual(
            issue?.message,
            "Sign-in, unlocking, and filling won’t work through the Safari "
                + "extension in Crest. The compatible route requires "
                + "1Password for Mac, the Chrome Web Store extension, the "
                + "official Crest for Mac release, and adding Crest as a trusted browser in "
                + "1Password."
        )
        XCTAssertEqual(issue?.technicalDetails, summary.errors)
    }

    func test1PasswordChromeFailureExplainsTheSigningAndTrustRequirements() {
        let summary = BrowserExtensionSummary(
            id: "aeblfdkhhhdcdjpifhhbdiojplfjncoa",
            displayName: "1Password – Password Manager",
            version: "8.12.30.21",
            requestedPermissions: ["nativeMessaging"],
            requestedHosts: ["<all_urls>"],
            unsupportedAPIs: [],
            errors: ["[Browser] (background/background.js:35:15906)"],
            isEnabled: true,
            isLoaded: true,
            permissionSnapshot: .empty,
            compatibilitySource: .chromeWebStore,
            sourceDisplayName: "Chrome Web Store"
        )

        let issue = BrowserExtensionSummaryPresentation.issue(for: summary)

        XCTAssertEqual(
            issue?.title,
            "1Password can’t connect to its companion app"
        )
        XCTAssertEqual(
            issue?.message,
            "1Password requires the production-signed Crest for Mac release. "
                + "Development-signed builds can’t complete sign-in, unlocking, "
                + "or filling. After installing Crest in Applications, add it in "
                + "1Password’s Browser settings."
        )
        XCTAssertEqual(issue?.technicalDetails, summary.errors)
    }

    func testICloudPasswordsLimitationRemainsVisibleAfterInstallation() {
        let summary = BrowserExtensionSummary(
            id: "pejdijmoenmkgeppbflobdenhhabjlaj",
            displayName: "iCloud Passwords",
            version: "3.3.0",
            requestedPermissions: ["nativeMessaging", "webNavigation"],
            requestedHosts: ["*://*/*"],
            unsupportedAPIs: [],
            errors: [],
            isEnabled: true,
            isLoaded: true,
            permissionSnapshot: .empty,
            compatibilitySource: .chromeWebStore,
            sourceDisplayName: "Chrome Web Store"
        )

        XCTAssertEqual(
            BrowserExtensionSummaryPresentation.detailText(
                for: summary,
                iCloudPasswordsCapability:
                    .missingManagedBrowserCredentialEntitlement
            ),
            "Limited compatibility · 2 permissions · 1 site rule"
        )
        let issue = BrowserExtensionSummaryPresentation.issue(
            for: summary,
            iCloudPasswordsCapability:
                .missingManagedBrowserCredentialEntitlement
        )
        XCTAssertEqual(
            issue?.title,
            "iCloud Passwords needs Apple browser approval"
        )
        XCTAssertEqual(
            issue?.message,
            "Password AutoFill won’t work in this Crest build. Apple requires "
                + "Crest to be signed with the managed Web Browser Public Key "
                + "Credential entitlement before its password helper will "
                + "connect. This build does not have that entitlement."
        )
        XCTAssertEqual(issue?.technicalDetails, [])
    }

    func testRemovalIntentLivesInTheExtensionsModel() throws {
        let space = try XCTUnwrap(BrowserSession.preview.spaces.first)
        let summary = makeSummary(
            requestedPermissions: [],
            requestedHosts: [],
            isEnabled: true,
            isLoaded: false
        )
        let model = BrowserExtensionsModel(
            space: space,
            extensionControllerPool: BrowserExtensionControllerPool()
        )

        model.requestRemoval(of: summary)
        XCTAssertEqual(model.pendingRemoval, summary)

        model.cancelRemoval()
        XCTAssertNil(model.pendingRemoval)
    }

    func testPlatformOptionsActionCarriesExactExtensionAndSpaceIdentity() {
        let spaceID = SpaceID()
        var receivedExtensionID: String?
        var receivedSpaceID: SpaceID?
        let actions = BrowserExtensionPlatformActions {
            receivedExtensionID = $0
            receivedSpaceID = $1
        }

        actions.openOptionsPage(
            extensionID: "extension-a",
            in: spaceID
        )

        XCTAssertTrue(actions.supportsOptionsPage)
        XCTAssertEqual(receivedExtensionID, "extension-a")
        XCTAssertEqual(receivedSpaceID, spaceID)
        XCTAssertFalse(BrowserExtensionPlatformActions.none.supportsOptionsPage)
    }

    func testAccessDecisionRawValuesStayStableWhileCopyLivesInPresentation() {
        XCTAssertEqual(
            BrowserExtensionAccessDecision.allCases.map(\.rawValue),
            ["ask", "allow", "block"]
        )
        XCTAssertEqual(
            BrowserExtensionAccessDecision.allCases.map {
                String(localized: $0.title)
            },
            ["Ask", "Allow", "Block"]
        )
    }

    func testCompatibilityErrorUsesPresentationOwnedDescription() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging"],
            source: .unpackedPackage,
            nativeMessagingCapability: .available
        )
        let error = BrowserExtensionCompatibilityError(
            assessment: assessment
        )

        XCTAssertEqual(
            error.localizedDescription,
            assessment.blockingIssues[0].message
        )
    }

    func testReviewedInstallGrantsOnlyTheRequiredAccessShownToTheUser() {
        let snapshot =
            BrowserExtensionInstallationPermissionPolicy
            .reviewedRequiredAccess(
                permissions: ["storage", "tabs"],
                hosts: ["<all_urls>"]
            )

        XCTAssertEqual(
            Set(snapshot.grantedPermissions.keys),
            ["storage", "tabs"]
        )
        XCTAssertEqual(
            Set(snapshot.grantedHosts.keys),
            ["<all_urls>"]
        )
        XCTAssertTrue(snapshot.deniedPermissions.isEmpty)
        XCTAssertTrue(snapshot.deniedHosts.isEmpty)
        XCTAssertFalse(snapshot.hasRequestedOptionalAccessToAllHosts)
    }

    private func makeSummary(
        requestedPermissions: [String],
        requestedHosts: [String],
        isEnabled: Bool,
        isLoaded: Bool,
        errors: [String] = [],
        compatibilitySource: BrowserExtensionCompatibilitySource =
            .chromeWebStore,
        compatibilityAssessment: BrowserExtensionCompatibilityAssessment =
            .compatible
    ) -> BrowserExtensionSummary {
        BrowserExtensionSummary(
            id: "test-extension",
            displayName: "Test Extension",
            version: "1.0",
            requestedPermissions: requestedPermissions,
            requestedHosts: requestedHosts,
            unsupportedAPIs: [],
            errors: errors,
            isEnabled: isEnabled,
            isLoaded: isLoaded,
            permissionSnapshot: .empty,
            compatibilitySource: compatibilitySource,
            compatibilityAssessment: compatibilityAssessment
        )
    }
}
