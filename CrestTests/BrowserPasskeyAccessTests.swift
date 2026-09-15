import JavaScriptCore
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

    func testConcurrentWebsiteRequestsWaitForTheSameSystemConsent() async {
        var requestCount = 0
        var consent: CheckedContinuation<BrowserPasskeyAuthorizationState, Never>?
        let controller = BrowserPasskeyAccessController(
            capabilityCheck: { true },
            deviceConfigurationCheck: { .configured },
            authorizationCheck: { .notDetermined },
            authorizationRequester: {
                requestCount += 1
                return await withCheckedContinuation { consent = $0 }
            }
        )
        controller.refreshStatus()
        let first = Task { await controller.requestAccess() }
        while consent == nil { await Task.yield() }
        var secondCompleted = false
        let second = Task {
            await controller.requestAccess()
            secondCompleted = true
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(secondCompleted, "Every caller must wait until consent resolves.")
        consent?.resume(returning: .authorized)
        await first.value
        await second.value
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(controller.status, .authorized)
    }

    func testWebsiteConsentPrecedesNativeRequestWithoutForwardingCredentialMaterial() throws {
        let context = try passkeyScriptContext()
        context.evaluateScript(
            """
            globalThis.options = {publicKey: {challenge: new Uint8Array([1, 2, 3])}};
            navigator.credentials.get(options);
            """)
        XCTAssertEqual(context.evaluateScript("JSON.stringify(messages)")?.toString(), "[\"request\"]")
        XCTAssertEqual(context.evaluateScript("nativeCalls.length")?.toInt32(), 0)
        context.evaluateScript("resolveConsent(true)")
        XCTAssertEqual(context.evaluateScript("nativeCalls.length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("nativeCalls[0].options === options")?.toBool(), true)
        XCTAssertEqual(context.evaluateScript("nativeCalls[0].receiver === navigator.credentials")?.toBool(), true)
        XCTAssertNil(context.exception)
    }

    func testOnlySecureWebsiteOriginsCanRequestSystemConsent() {
        for host in ["example.com", "localhost", "127.0.0.1"] {
            XCTAssertTrue(
                BrowserPasskeyConsentBridge.allowsConsent(
                    from:
                        BrowserSiteOrigin(scheme: "https", host: host, port: 443)))
        }
        XCTAssertTrue(
            BrowserPasskeyConsentBridge.allowsConsent(
                from:
                    BrowserSiteOrigin(scheme: "http", host: "localhost", port: 8000)))
        XCTAssertFalse(
            BrowserPasskeyConsentBridge.allowsConsent(
                from:
                    BrowserSiteOrigin(scheme: "http", host: "example.com", port: 80)))
        XCTAssertFalse(
            BrowserPasskeyConsentBridge.allowsConsent(
                from:
                    BrowserSiteOrigin(scheme: "file", host: "localhost", port: 0)))
    }

    func testBackgroundAndNonPasskeyCallsDoNotPromptAndAbortPreventsNativeContinuation() throws {
        let context = try passkeyScriptContext()
        context.evaluateScript(
            """
            navigator.credentials.get({publicKey: {}, mediation: 'conditional'});
            navigator.credentials.get({publicKey: {}, mediation: 'silent'});
            navigator.credentials.get({password: true});
            globalThis.signal = {aborted: false, reason: 'cancelled'};
            navigator.credentials.create({publicKey: {}, signal}).catch(e => globalThis.failure = e);
            signal.aborted = true;
            resolveConsent(true);
            """)
        XCTAssertEqual(context.evaluateScript("messages.length")?.toInt32(), 1)
        XCTAssertEqual(context.evaluateScript("nativeCalls.length")?.toInt32(), 3)
        XCTAssertEqual(context.evaluateScript("failure")?.toString(), "cancelled")
        XCTAssertNil(context.exception)
    }

    private func passkeyScriptContext() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(
            """
            globalThis.isSecureContext = true;
            globalThis.document = {hasFocus: () => true};
            globalThis.messages = [];
            globalThis.nativeCalls = [];
            globalThis.CredentialsContainer = function() {};
            for (const method of ['create', 'get']) {
              CredentialsContainer.prototype[method] = function(options) {
                nativeCalls.push({receiver: this, options});
                return Promise.resolve('native result');
              };
            }
            globalThis.navigator = {credentials: new CredentialsContainer()};
            globalThis.webkit = {messageHandlers: {crestPasskeyConsent: {
              postMessage(message) {
                messages.push(message);
                return new Promise(resolve => globalThis.resolveConsent = resolve);
              }
            }}};
            """)
        context.evaluateScript(BrowserPasskeyConsentBridge.source)
        XCTAssertNil(context.exception)
        return context
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
