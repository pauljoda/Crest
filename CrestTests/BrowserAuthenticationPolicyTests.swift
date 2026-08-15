import Foundation
import XCTest

@testable import Crest

@MainActor
final class BrowserAuthenticationPolicyTests: XCTestCase {
    func testBasicAndDigestPromptOnlyForAWebsiteChallenge() {
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
                isProxy: false,
                previousFailureCount: 0
            ),
            .promptForCredentials
        )
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPDigest,
                isProxy: false,
                previousFailureCount: 1
            ),
            .promptForCredentials
        )
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
                isProxy: true,
                previousFailureCount: 0
            ),
            .performDefaultHandling
        )
    }

    func testCredentialFailuresAreBounded() {
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
                isProxy: false,
                previousFailureCount: BrowserAuthenticationPolicy.maximumCredentialAttempts
            ),
            .cancel
        )
    }

    func testCredentialAttemptCapPreservesBoundaryAndProxyHandling() {
        XCTAssertEqual(BrowserAuthenticationPolicy.maximumCredentialAttempts, 3)
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPDigest,
                isProxy: false,
                previousFailureCount: BrowserAuthenticationPolicy.maximumCredentialAttempts - 1
            ),
            .promptForCredentials
        )
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPDigest,
                isProxy: false,
                previousFailureCount: BrowserAuthenticationPolicy.maximumCredentialAttempts + 1
            ),
            .cancel
        )
        XCTAssertEqual(
            BrowserAuthenticationPolicy.handling(
                authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
                isProxy: true,
                previousFailureCount: BrowserAuthenticationPolicy.maximumCredentialAttempts + 1
            ),
            .performDefaultHandling
        )
    }

    func testTrustAndClientCertificateChallengesRemainSystemOwned() {
        for method in [
            NSURLAuthenticationMethodServerTrust,
            NSURLAuthenticationMethodClientCertificate,
            NSURLAuthenticationMethodNTLM,
        ] {
            XCTAssertEqual(
                BrowserAuthenticationPolicy.handling(
                    authenticationMethod: method,
                    isProxy: false,
                    previousFailureCount: 0
                ),
                .performDefaultHandling
            )
        }
    }

    func testPhysicalValidationTrustRequiresDedicatedIdentityAndExactFingerprint() {
        let fingerprint = String(repeating: "a", count: 64)

        XCTAssertTrue(
            BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: "com.pauldavis.crest.physical-validation",
                expectedCertificateSHA256: fingerprint,
                actualCertificateSHA256: fingerprint.uppercased()
            )
        )
        XCTAssertFalse(
            BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: "com.pauldavis.crest",
                expectedCertificateSHA256: fingerprint,
                actualCertificateSHA256: fingerprint
            )
        )
        XCTAssertFalse(
            BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: "com.pauldavis.crest.physical-validation",
                expectedCertificateSHA256: fingerprint,
                actualCertificateSHA256: String(repeating: "b", count: 64)
            )
        )
        XCTAssertFalse(
            BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: "com.pauldavis.crest.physical-validation",
                expectedCertificateSHA256: "not-a-sha256",
                actualCertificateSHA256: "not-a-sha256"
            )
        )
    }

    func testPhysicalValidationFingerprintRejectsMissingMalformedAndPaddedValues() {
        let fingerprint = String(repeating: "a", count: 64)

        for expected in [nil, " \(fingerprint)", "\(fingerprint) ", String(repeating: "a", count: 63)] {
            XCTAssertFalse(
                BrowserPhysicalValidationTrustPolicy.allows(
                    bundleIdentifier: BrowserPhysicalValidationTrustPolicy.bundleIdentifier,
                    expectedCertificateSHA256: expected,
                    actualCertificateSHA256: fingerprint
                )
            )
        }
        XCTAssertFalse(
            BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: BrowserPhysicalValidationTrustPolicy.bundleIdentifier,
                expectedCertificateSHA256: String(repeating: "g", count: 64),
                actualCertificateSHA256: String(repeating: "g", count: 64)
            )
        )
        XCTAssertFalse(
            BrowserPhysicalValidationTrustPolicy.allows(
                bundleIdentifier: BrowserPhysicalValidationTrustPolicy.bundleIdentifier,
                expectedCertificateSHA256: fingerprint,
                actualCertificateSHA256: "\(fingerprint)\n"
            )
        )
    }

    func testDescriptorIncludesNondefaultPortRealmAndTransportWarning() {
        let protectionSpace = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 8765,
            protocol: "http",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        XCTAssertEqual(
            BrowserHTTPAuthenticationDescriptor.sourceLabel(for: protectionSpace),
            "accounts.crest.test:8765"
        )
    }

    func testDescriptorOmitsDefaultHTTPSPort() {
        let protectionSpace = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPDigest
        )

        XCTAssertEqual(
            BrowserHTTPAuthenticationDescriptor.sourceLabel(for: protectionSpace),
            "accounts.crest.test"
        )
    }

    func testDescriptorPreservesChallengeMetadataAndDefaultHTTPSource() {
        let protectionSpace = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 80,
            protocol: "HTTP",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let descriptor = BrowserHTTPAuthenticationDescriptor(
            challenge: makeChallenge(
                protectionSpace: protectionSpace,
                previousFailureCount: 2
            )
        )

        XCTAssertEqual(descriptor.source, "accounts.crest.test")
        XCTAssertEqual(descriptor.realm, "Members")
        XCTAssertEqual(descriptor.authenticationMethod, NSURLAuthenticationMethodHTTPBasic)
        XCTAssertFalse(descriptor.isSecureTransport)
        XCTAssertEqual(descriptor.previousFailureCount, 2)
    }

    func testDescriptorUsesProductNameWhenProtectionSpaceHasNoHost() {
        let protectionSpace = URLProtectionSpace(
            host: "",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        XCTAssertEqual(
            BrowserHTTPAuthenticationDescriptor.sourceLabel(for: protectionSpace),
            ProductIdentity.name
        )
    }

    func testCredentialProtectionSpaceIncludesOriginRealmAndAuthenticationMethod() throws {
        let basic = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
        let digest = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPDigest
        )

        let basicScope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(basic))
        let digestScope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(digest))

        XCTAssertEqual(basicScope.origin.description, "https://accounts.crest.test")
        XCTAssertEqual(basicScope.credentialScope, .httpBasic(realm: "Members"))
        XCTAssertEqual(digestScope.credentialScope, .httpDigest(realm: "Members"))
        XCTAssertNotEqual(basicScope, digestScope)
    }

    func testCredentialProtectionSpaceRejectsProxyAndNonPasswordChallenges() {
        let trust = URLProtectionSpace(
            host: "accounts.crest.test",
            port: 443,
            protocol: "https",
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodServerTrust
        )
        let proxy = URLProtectionSpace(
            proxyHost: "proxy.crest.test",
            port: 8080,
            type: NSURLProtectionSpaceHTTPProxy,
            realm: "Proxy",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )

        XCTAssertNil(BrowserHTTPAuthenticationProtectionSpace(trust))
        XCTAssertNil(BrowserHTTPAuthenticationProtectionSpace(proxy))
    }

    func testAuthenticationPromptAndSaveRequestDescriptionsRedactPasswords() throws {
        let response = BrowserHTTPAuthenticationPromptResponse(
            username: "member",
            password: "response-secret",
            shouldSave: true
        )
        XCTAssertEqual(
            response.description,
            "BrowserHTTPAuthenticationPromptResponse(username: member, password: <redacted>, shouldSave: true)"
        )
        XCTAssertEqual(response.debugDescription, response.description)
        XCTAssertFalse(response.description.contains("response-secret"))

        let protectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(makeProtectionSpace())
        )
        let request = BrowserHTTPAuthenticationSaveRequest(
            protectionSpace: protectionSpace,
            username: "member",
            password: "save-secret",
            replacing: nil
        )
        XCTAssertEqual(
            request.description,
            "BrowserHTTPAuthenticationSaveRequest(protectionSpace: \(protectionSpace), username: member, password: <redacted>)"
        )
        XCTAssertEqual(request.debugDescription, request.description)
        XCTAssertFalse(request.description.contains("save-secret"))
    }

    func testTypedAuthenticationChallengeDrivesTheFrameworkNeutralSession() async throws {
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test")))
        )
        let protectionSpace = BrowserHTTPAuthenticationProtectionSpace(
            origin: origin,
            credentialScope: .httpBasic(realm: "Members")
        )
        let descriptor = BrowserHTTPAuthenticationDescriptor(
            source: "accounts.crest.test",
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic,
            isSecureTransport: true,
            previousFailureCount: 0
        )
        let challenge = BrowserAuthenticationChallenge(
            authenticationMethod: .httpBasic,
            isProxy: false,
            previousFailureCount: 0,
            protectionSpace: protectionSpace,
            descriptor: descriptor,
            proposedUsername: "proposed-member"
        )
        let session = BrowserHTTPAuthenticationSession(spaceID: SpaceID())

        let decision = await session.response(to: challenge) { prompt in
            XCTAssertEqual(prompt.descriptor, descriptor)
            XCTAssertEqual(prompt.suggestedUsername, "proposed-member")
            return BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "one-time-secret",
                shouldSave: false
            )
        }

        guard case .useCredential(let username, let password) = decision else {
            return XCTFail("Expected the typed session to resolve a credential")
        }
        XCTAssertEqual(username, "member")
        XCTAssertEqual(password, "one-time-secret")
    }

    func testFoundationResolutionPreservesItsExistingInitializerAndOneTimeAdapter() {
        let credential = URLCredential(
            user: "member",
            password: "secret",
            persistence: .forSession
        )
        let existingAPI = BrowserHTTPAuthenticationResolution(
            disposition: .useCredential,
            credential: credential
        )
        let adapted = BrowserHTTPAuthenticationResolution(
            BrowserHTTPAuthenticationDecision.useCredential(
                username: "member",
                password: "secret"
            )
        )

        XCTAssertEqual(existingAPI.disposition, .useCredential)
        XCTAssertEqual(existingAPI.credential?.persistence, .forSession)
        XCTAssertEqual(adapted.disposition, .useCredential)
        XCTAssertEqual(adapted.credential?.user, "member")
        XCTAssertEqual(adapted.credential?.password, "secret")
        XCTAssertEqual(adapted.credential?.persistence, URLCredential.Persistence.none)
    }

    func testSavedHTTPSCredentialIsReusedOnceAndMarkedUsedOnlyAfterSuccess() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace()
        let scope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(protectionSpace))
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: scope,
            username: "member",
            password: "stored-secret"
        )
        var prompts = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { _ in
            prompts += 1
            return nil
        }

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(resolution.credential?.user, "member")
        XCTAssertEqual(resolution.credential?.password, "stored-secret")
        XCTAssertEqual(prompts, 0)
        XCTAssertTrue(saves.isEmpty)

        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.replacing, stored.descriptor)
        XCTAssertEqual(saves.first?.password, "stored-secret")
    }

    func testRejectedSavedCredentialPromptsAndReplacesOnlyAfterAcceptedNavigation() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace()
        let scope = try XCTUnwrap(BrowserHTTPAuthenticationProtectionSpace(protectionSpace))
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: scope,
            username: "member",
            password: "old-secret"
        )
        var prompts: [BrowserHTTPAuthenticationPrompt] = []
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { _ in
            XCTFail("The first challenge should reuse the stored credential")
            return nil
        }
        let retry = await session.response(
            to: makeChallenge(
                protectionSpace: protectionSpace,
                proposedUsername: "member",
                previousFailureCount: 1
            )
        ) { prompt in
            prompts.append(prompt)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "new-secret",
                shouldSave: true
            )
        }

        XCTAssertEqual(retry.credential?.password, "new-secret")
        XCTAssertEqual(prompts.first?.suggestedUsername, "member")
        XCTAssertEqual(prompts.first?.allowsSaving, true)
        XCTAssertTrue(saves.isEmpty)

        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.replacing, stored.descriptor)
        XCTAssertEqual(saves.first?.password, "new-secret")
    }

    func testPlainHTTPCanSignInOnceButCannotLoadOrSaveACredential() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace(protocol: "http", port: 80)
        var loadCount = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in
                loadCount += 1
                return nil
            },
            saveCredential: { saves.append($0) }
        )

        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { prompt in
            XCTAssertFalse(prompt.allowsSaving)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "one-time-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(resolution.credential?.password, "one-time-secret")
        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(saves.isEmpty)
    }

    func testPrivateBrowsingHTTPSAuthenticationIsAlwaysOneTimeOnly() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace()
        var loadCount = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        var prompts: [BrowserHTTPAuthenticationPrompt] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            allowsCredentialSaving: false,
            loadCredential: { _ in
                loadCount += 1
                return nil
            },
            saveCredential: { saves.append($0) }
        )

        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { prompt in
            prompts.append(prompt)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "private-member",
                password: "one-time-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(resolution.credential?.password, "one-time-secret")
        XCTAssertEqual(prompts.first?.allowsSaving, false)
        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(saves.isEmpty)
    }

    func testDisablingCredentialStorageMakesAnExistingHTTPSAuthSessionOneTimeOnly() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace()
        var loadCount = 0
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in
                loadCount += 1
                return nil
            },
            saveCredential: { saves.append($0) }
        )

        session.setCredentialStorageEnabled(false)
        let resolution = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace)
        ) { prompt in
            XCTAssertFalse(prompt.allowsSaving)
            return BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "one-time-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(resolution.disposition, .useCredential)
        XCTAssertEqual(loadCount, 0)
        XCTAssertTrue(saves.isEmpty)
    }

    func testAuthenticationFailureClearsAPendingSaveRequest() async {
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: SpaceID(),
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(
            to: makeChallenge(protectionSpace: makeProtectionSpace())
        ) { _ in
            BrowserHTTPAuthenticationPromptResponse(
                username: "member",
                password: "not-accepted",
                shouldSave: true
            )
        }
        session.authenticationFailed()
        await session.authenticationSucceeded()

        XCTAssertTrue(saves.isEmpty)
    }

    func testCancelledRetryClearsTheStoredCredentialSaveRequest() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace()
        let typedProtectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(protectionSpace)
        )
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: typedProtectionSpace,
            username: "member",
            password: "rejected-secret"
        )
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(to: makeChallenge(protectionSpace: protectionSpace)) { _ in
            XCTFail("The stored credential should be attempted before prompting")
            return nil
        }
        let cancellation = await session.response(
            to: makeChallenge(protectionSpace: protectionSpace, previousFailureCount: 1)
        ) { prompt in
            XCTAssertEqual(prompt.suggestedUsername, "member")
            return nil
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(cancellation.disposition, .cancelAuthenticationChallenge)
        XCTAssertTrue(saves.isEmpty)
    }

    func testReplacementRequiresTheRejectedStoredUsernameToMatch() async throws {
        let spaceID = SpaceID()
        let protectionSpace = makeProtectionSpace()
        let typedProtectionSpace = try XCTUnwrap(
            BrowserHTTPAuthenticationProtectionSpace(protectionSpace)
        )
        let stored = makeCredential(
            spaceID: spaceID,
            protectionSpace: typedProtectionSpace,
            username: "stored-member",
            password: "old-secret"
        )
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: spaceID,
            loadCredential: { _ in stored },
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(to: makeChallenge(protectionSpace: protectionSpace)) { _ in
            XCTFail("The stored credential should be attempted before prompting")
            return nil
        }
        _ = await session.response(
            to: makeChallenge(
                protectionSpace: protectionSpace,
                proposedUsername: "server-proposed",
                previousFailureCount: 1
            )
        ) { prompt in
            XCTAssertEqual(prompt.suggestedUsername, "server-proposed")
            return BrowserHTTPAuthenticationPromptResponse(
                username: "different-member",
                password: "new-secret",
                shouldSave: true
            )
        }
        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertNil(saves.first?.replacing)
    }

    func testCredentialStorageSettingOnlyResetsWhenItsValueChanges() async {
        var saves: [BrowserHTTPAuthenticationSaveRequest] = []
        let session = BrowserHTTPAuthenticationSession(
            spaceID: SpaceID(),
            saveCredential: { saves.append($0) }
        )

        _ = await session.response(
            to: makeChallenge(protectionSpace: makeProtectionSpace())
        ) { _ in
            BrowserHTTPAuthenticationPromptResponse(
                username: "first-member",
                password: "first-secret",
                shouldSave: true
            )
        }
        session.setCredentialStorageEnabled(true)
        await session.authenticationSucceeded()

        _ = await session.response(
            to: makeChallenge(protectionSpace: makeProtectionSpace())
        ) { _ in
            BrowserHTTPAuthenticationPromptResponse(
                username: "second-member",
                password: "second-secret",
                shouldSave: true
            )
        }
        session.setCredentialStorageEnabled(false)
        await session.authenticationSucceeded()

        XCTAssertEqual(saves.count, 1)
        XCTAssertEqual(saves.first?.username, "first-member")
    }

    private func makeProtectionSpace(
        protocol scheme: String = "https",
        port: Int = 443
    ) -> URLProtectionSpace {
        URLProtectionSpace(
            host: "accounts.crest.test",
            port: port,
            protocol: scheme,
            realm: "Members",
            authenticationMethod: NSURLAuthenticationMethodHTTPBasic
        )
    }

    private func makeChallenge(
        protectionSpace: URLProtectionSpace,
        proposedUsername: String? = nil,
        previousFailureCount: Int = 0
    ) -> URLAuthenticationChallenge {
        URLAuthenticationChallenge(
            protectionSpace: protectionSpace,
            proposedCredential: proposedUsername.map {
                URLCredential(user: $0, password: "", persistence: .none)
            },
            previousFailureCount: previousFailureCount,
            failureResponse: nil,
            error: nil,
            sender: AuthenticationChallengeSenderStub()
        )
    }

    private func makeCredential(
        spaceID: SpaceID,
        protectionSpace: BrowserHTTPAuthenticationProtectionSpace,
        username: String,
        password: String
    ) -> BrowserCredential {
        BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: protectionSpace.origin,
                scope: protectionSpace.credentialScope,
                username: username,
                createdAt: Date(timeIntervalSince1970: 1_000)
            ),
            password: password
        )
    }
}

private final class AuthenticationChallengeSenderStub: NSObject, URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {}
    func cancel(_ challenge: URLAuthenticationChallenge) {}
    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {}
    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {}
}
