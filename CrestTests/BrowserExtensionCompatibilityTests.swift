import XCTest

@testable import Crest

final class BrowserExtensionCompatibilityTests: XCTestCase {
    func testMacOSAppSandboxCapabilityBoundary() {
        XCTAssertEqual(
            BrowserPlatformExtensionNativeMessagingCapability.macOS(
                appSandboxEnabled: false
            ),
            .available
        )
        XCTAssertEqual(
            BrowserPlatformExtensionNativeMessagingCapability.macOS(
                appSandboxEnabled: true
            ),
            .unavailableInAppSandbox
        )
    }

    func testMacOSManagedBrowserCredentialCapabilityBoundary() {
        XCTAssertEqual(
            BrowserICloudPasswordsCapability.macOS(
                hasManagedBrowserCredentialEntitlement: true
            ),
            .available
        )
        XCTAssertEqual(
            BrowserICloudPasswordsCapability.macOS(
                hasManagedBrowserCredentialEntitlement: false
            ),
            .missingManagedBrowserCredentialEntitlement
        )
    }

    func testSandboxedChromeWebStoreExtensionRequiringNativeMessagingIsBlocked() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging", "storage"],
            source: .chromeWebStore,
            nativeMessagingCapability: .unavailableInAppSandbox
        )

        XCTAssertFalse(assessment.canRun)
        XCTAssertEqual(
            assessment.blockingIssues.map(\.kind),
            [.nativeMessagingUnavailable]
        )
    }

    func testMacReleaseAllowsVerifiedChromeWebStoreNativeMessaging() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging"],
            source: .chromeWebStore,
            nativeMessagingCapability: .available
        )

        XCTAssertTrue(assessment.canRun)
        XCTAssertTrue(assessment.issues.isEmpty)
    }

    func testKnownICloudPasswordsPackageHasClearNonblockingRuntimeWarning() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            extensionID: "pejdijmoenmkgeppbflobdenhhabjlaj",
            requestedPermissions: ["nativeMessaging", "webNavigation"],
            source: .chromeWebStore,
            nativeMessagingCapability: .available,
            iCloudPasswordsCapability:
                .missingManagedBrowserCredentialEntitlement
        )

        XCTAssertTrue(assessment.canRun)
        XCTAssertEqual(
            assessment.issues.map(\.kind),
            [.knownRuntimeLimitation]
        )
        XCTAssertFalse(assessment.issues[0].isBlocking)
        XCTAssertEqual(
            BrowserExtensionCompatibilityPresentation.message(
                for: assessment.issues[0].kind
            ),
            "Password AutoFill won’t work in this Crest build. Apple requires "
                + "Crest to be signed with the managed Web Browser Public Key "
                + "Credential entitlement before its password helper will "
                + "connect. This build does not have that entitlement."
        )
    }

    func testApprovedBrowserCredentialEntitlementRemovesICloudWarning() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            extensionID: "pejdijmoenmkgeppbflobdenhhabjlaj",
            requestedPermissions: ["nativeMessaging", "webNavigation"],
            source: .chromeWebStore,
            nativeMessagingCapability: .available,
            iCloudPasswordsCapability: .available
        )

        XCTAssertTrue(assessment.canRun)
        XCTAssertTrue(assessment.issues.isEmpty)
    }

    func testUnpackedExtensionRequiringNativeMessagingRemainsBlocked() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging"],
            source: .unpackedPackage,
            nativeMessagingCapability: .available
        )

        XCTAssertFalse(assessment.canRun)
        XCTAssertEqual(
            assessment.blockingIssues.map(\.kind),
            [.unverifiedNativeMessaging]
        )
    }

    func testForeignSafariAppNativeHandlerIsNotPresentedAsPortable() {
        let assessment = BrowserExtensionCompatibilityPolicy.assess(
            requestedPermissions: ["nativeMessaging"],
            source: .safariAppExtensionBundle,
            nativeMessagingCapability: .available
        )

        XCTAssertFalse(assessment.canRun)
        XCTAssertEqual(
            assessment.blockingIssues.map(\.kind),
            [.foreignSafariNativeHandler]
        )
    }

    func testPopularWebOnlyExtensionCapabilitiesRemainEligible() {
        let permissionSets = [
            ["storage", "scripting"],
            ["declarativeNetRequest", "contextMenus"],
            ["tabs", "webNavigation", "unlimitedStorage"],
        ]

        for permissions in permissionSets {
            let assessment = BrowserExtensionCompatibilityPolicy.assess(
                requestedPermissions: permissions,
                source: .chromeWebStore,
                nativeMessagingCapability: .unavailableInAppSandbox
            )

            XCTAssertTrue(
                assessment.canRun,
                "Unexpectedly blocked \(permissions)"
            )
        }
    }

    @MainActor
    func testCompatibilityProjectionDoesNotRewritePersistedErrors() throws {
        let spaceID = SpaceID()
        let installation = BrowserExtensionInstallation(
            id: "local.native-companion",
            spaceID: spaceID,
            packageName: "native-companion",
            source: .unpackedPackage,
            displayName: "Native Companion",
            version: "1.0",
            requestedPermissions: ["nativeMessaging"],
            requestedHosts: [],
            unsupportedAPIs: [],
            errors: ["Existing runtime failure"],
            isEnabled: true,
            permissionSnapshot: .empty,
            installedAt: Date(timeIntervalSince1970: 100),
            modifiedAt: Date(timeIntervalSince1970: 200)
        )
        let persistence = InMemoryBrowserExtensionRegistryPersistence(
            installations: [installation]
        )
        let registry = BrowserExtensionRegistry(persistence: persistence)
        let pool = BrowserExtensionControllerPool(registry: registry)

        let summary = try XCTUnwrap(pool.extensions(in: spaceID).first)

        XCTAssertEqual(summary.errors, ["Existing runtime failure"])
        XCTAssertEqual(
            summary.compatibilityAssessment.blockingIssues.map(\.kind),
            [.unverifiedNativeMessaging]
        )
        XCTAssertEqual(
            registry.installation(
                extensionID: installation.id,
                in: spaceID
            )?.errors,
            ["Existing runtime failure"]
        )
    }
}
