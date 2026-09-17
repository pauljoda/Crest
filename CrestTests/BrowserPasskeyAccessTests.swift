import XCTest

@testable import Crest

@MainActor
final class BrowserPasskeyAccessTests: XCTestCase {
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

    func testCheckingStatusAcrossRelaunchesNeverRequestsSystemConsent() async {
        var requests = 0
        for state in [BrowserPasskeyAuthorizationState.notDetermined, .authorized, .denied] {
            for _ in 0..<2 {
                let controller = BrowserPasskeyAccessController(
                    capabilityCheck: { true },
                    deviceConfigurationCheck: { .configured },
                    authorizationCheck: { state },
                    authorizationRequester: {
                        requests += 1
                        return .authorized
                    }
                )
                await controller.prepareForBrowsing()
                controller.refreshStatus()
                XCTAssertEqual(
                    requests, 0,
                    "Navigation and status checks must never request passkey consent, even after a relaunch.")
            }
        }
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
