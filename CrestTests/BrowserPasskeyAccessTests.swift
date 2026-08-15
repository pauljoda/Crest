import XCTest

@testable import Crest

@MainActor
final class BrowserPasskeyAccessTests: XCTestCase {
    func testPrivacyBoundaryKeepsSystemCredentialsGlobalAndWebsiteSessionsSpaceIsolated() {
        XCTAssertEqual(
            BrowserPasskeyPrivacyBoundary.webKit.credentialAccess,
            .applicationWideSystemProvider
        )
        XCTAssertEqual(
            BrowserPasskeyPrivacyBoundary.webKit.websiteSession,
            .spaceIsolated
        )
        XCTAssertFalse(BrowserPasskeyPrivacyBoundary.webKit.storesCredentialInventoryInCrest)
    }

    func testManagedCapabilityIsRequiredBeforeEveryOtherStatus() {
        XCTAssertEqual(
            BrowserPasskeyAccessPolicy.status(
                hasManagedCapability: false,
                deviceConfiguration: .configured,
                authorizationState: .authorized
            ),
            .managedCapabilityRequired
        )
    }

    func testDeviceConfigurationAndAuthorizationMapToExplicitStatuses() {
        XCTAssertEqual(
            BrowserPasskeyAccessPolicy.status(
                hasManagedCapability: true,
                deviceConfiguration: .notConfigured,
                authorizationState: .authorized
            ),
            .deviceNotConfigured
        )
        XCTAssertEqual(
            BrowserPasskeyAccessPolicy.status(
                hasManagedCapability: true,
                deviceConfiguration: .unknown,
                authorizationState: .notDetermined
            ),
            .notDetermined
        )
        XCTAssertEqual(
            BrowserPasskeyAccessPolicy.status(
                hasManagedCapability: true,
                deviceConfiguration: .configured,
                authorizationState: .authorized
            ),
            .authorized
        )
        XCTAssertEqual(
            BrowserPasskeyAccessPolicy.status(
                hasManagedCapability: true,
                deviceConfiguration: .configured,
                authorizationState: .denied
            ),
            .denied
        )
    }

    func testControllerRequestsAccessOnlyAfterAnExplicitEligibleAction() async {
        var requestCount = 0
        var systemAuthorization = BrowserPasskeyAuthorizationState.notDetermined
        let controller = BrowserPasskeyAccessController(
            capabilityCheck: { true },
            deviceConfigurationCheck: { .configured },
            authorizationCheck: { systemAuthorization },
            authorizationRequester: {
                requestCount += 1
                systemAuthorization = .authorized
                return .authorized
            }
        )

        XCTAssertEqual(requestCount, 0)
        XCTAssertEqual(controller.status, .checking)

        controller.refreshStatus()
        XCTAssertEqual(controller.status, .notDetermined)
        XCTAssertTrue(controller.canRequestAccess)

        await controller.requestAccess()
        await controller.requestAccess()

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.status, .authorized)
        XCTAssertFalse(controller.canRequestAccess)
        XCTAssertFalse(controller.isRequesting)
    }

    func testControllerNeverRequestsWithoutTheManagedCapability() async {
        var deviceConfigurationCheckCount = 0
        var authorizationCheckCount = 0
        var requestCount = 0
        let controller = BrowserPasskeyAccessController(
            capabilityCheck: { false },
            deviceConfigurationCheck: {
                deviceConfigurationCheckCount += 1
                return .configured
            },
            authorizationCheck: {
                authorizationCheckCount += 1
                return .notDetermined
            },
            authorizationRequester: {
                requestCount += 1
                return .authorized
            }
        )

        controller.refreshStatus()
        await controller.requestAccess()

        XCTAssertEqual(controller.status, .managedCapabilityRequired)
        XCTAssertEqual(deviceConfigurationCheckCount, 0)
        XCTAssertEqual(authorizationCheckCount, 0)
        XCTAssertEqual(requestCount, 0)
        XCTAssertFalse(controller.canRequestAccess)
    }

    func testSystemPasswordWriteThroughRequiresMobileAPIAndManagedBrowserCapability() {
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughPolicy.availability(
                isMobilePlatform: false,
                supportsSystemAPI: true,
                hasManagedBrowserCapability: true,
                isLaunchIsolated: false
            ),
            .unsupportedPlatform
        )
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughPolicy.availability(
                isMobilePlatform: true,
                supportsSystemAPI: false,
                hasManagedBrowserCapability: true,
                isLaunchIsolated: false
            ),
            .systemVersionRequired
        )
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughPolicy.availability(
                isMobilePlatform: true,
                supportsSystemAPI: true,
                hasManagedBrowserCapability: false,
                isLaunchIsolated: false
            ),
            .managedBrowserCapabilityRequired
        )
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughPolicy.availability(
                isMobilePlatform: true,
                supportsSystemAPI: true,
                hasManagedBrowserCapability: true,
                isLaunchIsolated: false
            ),
            .available
        )
        XCTAssertEqual(
            BrowserSystemPasswordWriteThroughPolicy.availability(
                isMobilePlatform: true,
                supportsSystemAPI: true,
                hasManagedBrowserCapability: true,
                isLaunchIsolated: true
            ),
            .isolatedLaunch
        )
    }

    func testSystemPasswordWriteThroughRequiresAnEnabledOrdinarySpace() {
        var preferences = BrowserCredentialPreferences.default

        XCTAssertFalse(
            BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
                preferences: preferences,
                availability: .available,
                isPrivateBrowsing: false
            )
        )

        preferences.alsoOffersSaveToSystemPasswords = true
        XCTAssertTrue(
            BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
                preferences: preferences,
                availability: .available,
                isPrivateBrowsing: false
            )
        )
        XCTAssertFalse(
            BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
                preferences: preferences,
                availability: .managedBrowserCapabilityRequired,
                isPrivateBrowsing: false
            )
        )
        XCTAssertFalse(
            BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
                preferences: preferences,
                availability: .available,
                isPrivateBrowsing: true
            )
        )
        XCTAssertFalse(
            BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
                preferences: preferences,
                availability: .isolatedLaunch,
                isPrivateBrowsing: false
            )
        )
    }
}
