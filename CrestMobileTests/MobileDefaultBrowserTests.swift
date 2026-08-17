import XCTest

@testable import CrestMobile

@MainActor
final class MobileDefaultBrowserTests: XCTestCase {
    func testMobileApplicationKeepsTheProductionCrestBundleIdentityByDefault() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.pauldavis.crest")
    }

    func testMobileApplicationBundlesTheMinimalCrestPrivacyManifest() throws {
        let manifestURL = try XCTUnwrap(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        )
        let data = try Data(contentsOf: manifestURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )

        XCTAssertEqual(
            Set(manifest.keys),
            [
                "NSPrivacyTracking",
                "NSPrivacyCollectedDataTypes",
                "NSPrivacyAccessedAPITypes",
            ])
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertNil(manifest["NSPrivacyTrackingDomains"])
        let collectedDataTypes = try XCTUnwrap(
            manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        )
        XCTAssertTrue(collectedDataTypes.isEmpty)

        let entries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )
        let reasons = try Dictionary(
            uniqueKeysWithValues: entries.map { entry in
                (
                    try XCTUnwrap(entry["NSPrivacyAccessedAPIType"] as? String),
                    try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String])
                )
            })
        XCTAssertEqual(
            reasons,
            [
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]
            ])
    }

    func testPasskeyBuildManifestIsEnabledAfterTheManagedEntitlementIsProvisioned() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "CrestBrowserPasskeyManagedCapability"
            ) as? Bool,
            true
        )
    }

    func testSystemPasswordWriteThroughManifestIsEnabledAfterBrowserApproval() {
        XCTAssertEqual(
            Bundle.main.object(
                forInfoDictionaryKey: "CrestSystemPasswordWriteThroughManagedCapability"
            ) as? Bool,
            true
        )
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughSystem.availability(
                for: BrowserLaunchEnvironment(
                    values: [:],
                    isXCTestRuntime: false
                )
            ),
            .available
        )
    }

    func testIsolatedLaunchRejectsSystemPasswordWriteThroughBeforePresentation()
        async throws
    {
        let origin = try XCTUnwrap(
            CredentialOrigin(
                url: try XCTUnwrap(URL(string: "https://accounts.example.com"))
            )
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: .now
        )

        do {
            try await BrowserSystemPasswordWriteThroughSystem.offer(
                candidate: candidate,
                title: "Isolated",
                anchor: nil
            )
            XCTFail("An isolated launch must not reach ASCredentialDataManager.")
        } catch {
            XCTAssertEqual(
                error as? BrowserSystemPasswordWriteThroughError,
                .unavailable
            )
        }
    }

    func testMobileApplicationRegistersBothWebURLSchemes() throws {
        let urlTypes = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
                as? [[String: Any]]
        )
        let schemes = Set(
            urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )

        XCTAssertTrue(schemes.contains("http"))
        XCTAssertTrue(schemes.contains("https"))
    }

    func testMobileApplicationSupportsIndependentNativeWindowScenes() throws {
        let sceneManifest = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest")
                as? [String: Any]
        )

        XCTAssertEqual(
            sceneManifest["UIApplicationSupportsMultipleScenes"] as? Bool,
            true
        )
    }

    func testDefaultBrowserStatusIsNeverPolledByControllerInitialization() {
        var statusCheckCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .systemSettings,
            statusCheck: {
                statusCheckCount += 1
                return false
            },
            defaultRequest: {},
            settingsOpener: {}
        )

        XCTAssertEqual(statusCheckCount, 0)
        XCTAssertEqual(controller.status, .unknown)

        controller.refreshStatus()

        XCTAssertEqual(statusCheckCount, 1)
        XCTAssertEqual(controller.status, .notDefault)
    }

    func testApprovedDefaultBrowserFlowOpensSystemSettingsWithoutImplicitStatusCheck() {
        var statusCheckCount = 0
        var settingsOpenCount = 0
        let controller = BrowserDefaultBrowserController(
            requestStyle: .systemSettings,
            statusCheck: {
                statusCheckCount += 1
                return false
            },
            defaultRequest: {},
            settingsOpener: { settingsOpenCount += 1 }
        )

        XCTAssertEqual(controller.requestStyle, .systemSettings)
        controller.openSystemSettings()

        XCTAssertEqual(settingsOpenCount, 1)
        XCTAssertEqual(statusCheckCount, 0)
        XCTAssertEqual(controller.status, .unknown)
    }

    func testMobileExternalURLPolicyRejectsNonWebSchemes() throws {
        XCTAssertTrue(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "https://example.com"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "javascript:alert(1)"))
            )
        )
        XCTAssertFalse(
            BrowserExternalURLPolicy.accepts(
                try XCTUnwrap(URL(string: "data:text/plain,hello"))
            )
        )
    }

    func testMobileOutboundSchemesLeaveWebKitOrAreBlocked() throws {
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "https://example.com"))
            ),
            .webKit
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "data:text/plain,hello"))
            ),
            .webKit
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "tel:+15555550100"))
            ),
            .handOff
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "sms:+15555550100"))
            ),
            .handOff
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "javascript:alert(1)"))
            ),
            .blocked
        )
        XCTAssertEqual(
            BrowserExternalSchemePolicy.disposition(
                for: try XCTUnwrap(URL(string: "file:///tmp/index.html"))
            ),
            .blocked
        )
    }

    func testMobileScriptedExternalSchemePromptsWithoutARememberedApproval() {
        XCTAssertEqual(
            BrowserExternalSchemeConsent.resolve(trigger: .scripted, decision: .ask),
            .prompt
        )
        XCTAssertEqual(
            BrowserExternalSchemeConsent.resolve(
                trigger: .scripted,
                decision: .grantPersistently
            ),
            .open
        )
        XCTAssertEqual(
            BrowserExternalSchemeConsent.resolve(
                trigger: .explicitUserNavigation,
                decision: .ask
            ),
            .prompt
        )
    }

}
