import WebKit
import XCTest
@testable import CrestMobile

@MainActor
final class MobileBrowserCredentialTests: XCTestCase {
    func testMobilePageInstallsTheSharedCredentialBridgeInEveryFrame() {
        let space = makeSpace(index: 1)
        let page = MobileBrowserPage(tab: space.tabs[0], space: space, openNewTab: { _ in })
        let scripts = page.webView.configuration.userContentController.userScripts

        XCTAssertTrue(scripts.contains {
            $0.source == BrowserCredentialContentBridge.source
                && $0.injectionTime == .atDocumentStart
                && !$0.isForMainFrameOnly
        })
    }

    func testMobilePageReceivesASuccessfulIsolatedWorldFormSubmission() async throws {
        let space = makeSpace(index: 7)
        let page = MobileBrowserPage(tab: space.tabs[0], space: space, openNewTab: { _ in })
        let request = URLRequest(url: URL(string: "https://forms.crest.test/login")!)
        page.webView.loadSimulatedRequest(request, responseHTML: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="mobile-login">
          <input autocomplete="username" value="mobile@example.com">
          <input type="password" autocomplete="current-password" value="mobile-secret">
          <button type="button">Sign In</button>
        </form>
        """)
        try await waitUntil { page.completedNavigationCount == 1 }

        let didCapture = try await page.webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": "#mobile-login"],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        XCTAssertEqual(didCapture as? Bool, true)
        XCTAssertNil(page.credentialSaveCandidate)

        _ = try await page.webView.callAsyncJavaScript(
            "document.querySelector('#mobile-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        try await waitUntil { page.credentialSaveCandidate != nil }

        let candidate = try XCTUnwrap(page.credentialSaveCandidate)
        XCTAssertEqual(candidate.username, "mobile@example.com")
        XCTAssertEqual(candidate.password, "mobile-secret")
        XCTAssertEqual(candidate.origin, try origin("https://forms.crest.test/login"))
        XCTAssertFalse(candidate.description.contains("mobile-secret"))
        page.dismissCredentialSaveCandidate()
    }

    func testFillContextRejectsAnotherSpaceAndAnotherOrigin() throws {
        let owningSpace = makeSpace(index: 2)
        let otherSpace = makeSpace(index: 3)
        let loginOrigin = try origin("https://accounts.example.com/login")
        let otherOrigin = try origin("https://other.example.com/login")
        let state = BrowserCredentialPageState<String>(spaceID: owningSpace.id)
        let focus = try message([
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": "login-form",
            "username": "person@example.com",
            "passwordKind": "current"
        ])

        state.receive(
            focus,
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )
        let request = try XCTUnwrap(state.fillRequest)

        XCTAssertThrowsError(try state.fillContext(
            for: request.id,
            credential: credential(spaceID: otherSpace.id, origin: loginOrigin)
        )) { error in
            XCTAssertEqual(error as? BrowserCredentialFillError, .staleOrMismatchedRequest)
        }
        XCTAssertThrowsError(try state.fillContext(
            for: request.id,
            credential: credential(spaceID: owningSpace.id, origin: otherOrigin)
        )) { error in
            XCTAssertEqual(error as? BrowserCredentialFillError, .staleOrMismatchedRequest)
        }

        let context = try state.fillContext(
            for: request.id,
            credential: credential(spaceID: owningSpace.id, origin: loginOrigin)
        )
        XCTAssertEqual(context.target, "main-frame")
        state.completeFill(username: "person@example.com", requestID: request.id)
        XCTAssertNil(state.fillRequest)
    }

    func testTrustedSecureNewPasswordFocusCreatesAGenerationOnlyRequest() throws {
        let space = makeSpace(index: 8)
        let loginOrigin = try origin("https://accounts.example.com/settings/password")
        let state = BrowserCredentialPageState<String>(spaceID: space.id)
        let focus = try message([
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": "change-password",
            "username": "person@example.com",
            "passwordKind": "new"
        ])

        state.receive(
            focus,
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: "main-frame"
        )

        let request = try XCTUnwrap(state.fillRequest)
        XCTAssertEqual(request.passwordKind, .new)
        XCTAssertEqual(request.usernameHint, "person@example.com")
        XCTAssertThrowsError(try state.fillContext(
            for: request.id,
            credential: credential(spaceID: space.id, origin: loginOrigin)
        )) { error in
            XCTAssertEqual(error as? BrowserCredentialFillError, .staleOrMismatchedRequest)
        }

        let context = try state.generatedPasswordFillContext(for: request.id)
        XCTAssertEqual(context.request, request)
        XCTAssertEqual(context.target, "main-frame")
        state.completeGeneratedPasswordFill(requestID: request.id)
        XCTAssertNil(state.fillRequest)
    }

    func testSuccessfulDocumentTransitionOffersARedactedSpaceOwnedSaveCandidate() throws {
        let space = makeSpace(index: 4)
        let loginOrigin = try origin("https://accounts.example.com/login")
        let state = BrowserCredentialPageState<String>(spaceID: space.id)
        let submit = try message([
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "login-form",
            "username": "person@example.com",
            "password": "mobile-secret",
            "passwordKind": "current"
        ])
        let success = try message([
            "version": 1,
            "event": "documentState",
            "trusted": false,
            "hasVisiblePasswordField": false
        ])

        state.receive(
            submit,
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: nil
        )
        XCTAssertNil(state.saveCandidate, "Submitting alone must not be treated as a successful login")

        state.receive(
            success,
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            isMainFrame: true,
            fillTarget: nil
        )
        let candidate = try XCTUnwrap(state.saveCandidate)
        XCTAssertEqual(candidate.password, "mobile-secret")
        XCTAssertFalse(candidate.description.contains("mobile-secret"))

        state.webContentProcessDidTerminate()
        XCTAssertNil(state.fillRequest)
        XCTAssertNil(state.saveCandidate)
    }

    func testSameSiteCredentialsStayIndependentAcrossMobileSpaces() async throws {
        let first = makeSpace(index: 5)
        let second = makeSpace(index: 6)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [first, second], selectedSpaceID: first.id),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let url = URL(string: "https://accounts.example.com/login")!

        let firstDescriptor = try await browser.saveCredential(
            username: "same@example.com",
            password: "first-space-secret",
            for: url,
            in: first.id
        )
        let secondDescriptor = try await browser.saveCredential(
            username: "same@example.com",
            password: "second-space-secret",
            for: url,
            in: second.id
        )

        let firstSuggestions = try await browser.credentialSuggestions(for: url, in: first.id)
        let secondSuggestions = try await browser.credentialSuggestions(for: url, in: second.id)
        let firstCredential = try await browser.credential(id: firstDescriptor.id, in: first.id)
        let crossSpaceCredential = try await browser.credential(id: firstDescriptor.id, in: second.id)

        XCTAssertEqual(firstSuggestions, [firstDescriptor])
        XCTAssertEqual(secondSuggestions, [secondDescriptor])
        XCTAssertEqual(firstCredential?.password, "first-space-secret")
        XCTAssertNil(crossSpaceCredential)
    }

    func testMobileFormLifecycleCreatesSuppressesUpdatesAndDeletesInsideOneSpace() async throws {
        let first = makeSpace(index: 8)
        let second = makeSpace(index: 9)
        let browser = BrowserStore(
            session: BrowserSession(spaces: [first, second], selectedSpaceID: first.id),
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let submittedAt = Date(timeIntervalSince1970: 9_000)
        let pageOrigin = try origin("https://accounts.crest.test/login")
        let original = candidate(
            origin: pageOrigin,
            password: "original-secret",
            submittedAt: submittedAt
        )

        let created = try await browser.commitCredentialSave(
            original,
            in: first.id,
            now: submittedAt
        )
        let unchanged = try await browser.credentialSavePlan(
            for: original,
            in: first.id,
            now: submittedAt
        )
        guard case .alreadyStored = unchanged else {
            return XCTFail("An identical mobile sign-in should not prompt again")
        }

        let changedAt = submittedAt.addingTimeInterval(5)
        let changed = candidate(
            origin: pageOrigin,
            password: "updated-secret",
            submittedAt: changedAt
        )
        let updated = try await browser.commitCredentialSave(
            changed,
            in: first.id,
            now: changedAt
        )

        XCTAssertEqual(updated.disposition, .updated)
        XCTAssertEqual(updated.descriptor.id, created.descriptor.id)
        let secondInventory = try await browser.savedCredentialDescriptors(in: second.id)
        XCTAssertEqual(secondInventory, [])

        try await browser.deleteCredential(id: updated.descriptor.id, in: first.id)
        let firstInventory = try await browser.savedCredentialDescriptors(in: first.id)
        XCTAssertEqual(firstInventory, [])
    }

    func testHostileCredentialMessagesRemainRejectedInTheMobileModule() {
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": false,
            "formID": "forged",
            "passwordKind": "current"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": "exfiltration",
            "password": "must-not-cross",
            "passwordKind": "current"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 2,
            "event": "submit",
            "trusted": true,
            "formID": "wrong-version",
            "username": "person",
            "password": "secret",
            "passwordKind": "current"
        ]))
    }

    private func credential(spaceID: SpaceID, origin: CredentialOrigin) -> BrowserCredential {
        BrowserCredential(
            descriptor: CredentialDescriptor(
                spaceID: spaceID,
                origin: origin,
                username: "person@example.com"
            ),
            password: "secret"
        )
    }

    private func message(_ body: [String: Any]) throws -> BrowserCredentialFormMessage {
        try XCTUnwrap(BrowserCredentialFormMessage(body: body))
    }

    private func origin(_ value: String) throws -> CredentialOrigin {
        try XCTUnwrap(CredentialOrigin(url: try XCTUnwrap(URL(string: value))))
    }

    private func candidate(
        origin: CredentialOrigin,
        password: String,
        submittedAt: Date
    ) -> BrowserCredentialSaveCandidate {
        BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: password,
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
        )
    }

    private func makeSpace(index: Int) -> BrowserSpace {
        let tab = BrowserTab(
            id: TabID(rawValue: fixedUUID(index * 10 + 1)),
            title: "New Tab",
            url: nil,
            placement: .current
        )
        return BrowserSpace(
            id: SpaceID(rawValue: fixedUUID(index * 10 + 2)),
            profile: BrowsingProfile(id: fixedUUID(index * 10 + 3)),
            name: "Space \(index)",
            symbol: "circle",
            accent: .indigo,
            folders: [],
            tabs: [tab],
            selectedTabID: tab.id
        )
    }

    private func fixedUUID(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012x", value))!
    }

    private func waitUntil(
        timeout: Duration = .seconds(8),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for the mobile WebKit credential state")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
