import Foundation
import WebKit
import XCTest
@testable import Crest

@MainActor
final class BrowserCredentialFormTests: XCTestCase {
    func testFocusMessageRequiresATrustedGestureAndNeverAcceptsAPassword() throws {
        let valid = try XCTUnwrap(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": "form-1",
            "username": "person@example.com",
            "passwordKind": "current"
        ]))

        XCTAssertEqual(valid.event, .focus)
        XCTAssertEqual(valid.formID, "form-1")
        XCTAssertEqual(valid.username, "person@example.com")
        XCTAssertNil(valid.password)
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": false,
            "formID": "form-1"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": "form-1"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": "form-1",
            "password": "page-tried-to-exfiltrate-this"
        ]))
    }

    func testSubmitMessageRequiresCompleteTrustedFieldsAndRedactsItsSecret() throws {
        let message = try XCTUnwrap(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "form-7",
            "username": "person",
            "password": "correct horse battery staple",
            "passwordKind": "new"
        ]))

        XCTAssertEqual(message.event, .submit)
        XCTAssertEqual(message.username, "person")
        XCTAssertEqual(message.password, "correct horse battery staple")
        XCTAssertEqual(message.passwordKind, .new)
        XCTAssertFalse(message.description.contains("correct horse battery staple"))
        XCTAssertTrue(message.description.contains("<redacted>"))

        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "submit",
            "trusted": false,
            "formID": "form-7",
            "username": "person",
            "password": "secret",
            "passwordKind": "current"
        ]))
        let passwordOnlyStep = try XCTUnwrap(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "form-7",
            "password": "secret",
            "passwordKind": "current"
        ]))
        XCTAssertNil(passwordOnlyStep.username)
        XCTAssertEqual(passwordOnlyStep.password, "secret")
    }

    func testUsernameStepRequiresATrustedBoundedUsernameAndNoPassword() throws {
        let message = try XCTUnwrap(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "username",
            "trusted": true,
            "formID": "form-username",
            "username": "person@example.com"
        ]))
        XCTAssertEqual(message.event, .username)
        XCTAssertEqual(message.username, "person@example.com")
        XCTAssertNil(message.password)

        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "username",
            "trusted": false,
            "formID": "form-username",
            "username": "person@example.com"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "username",
            "trusted": true,
            "formID": "form-username",
            "username": "person@example.com",
            "password": "must-not-cross-this-message"
        ]))
    }

    func testDocumentStateContractDoesNotAcceptCredentialFields() throws {
        let state = try XCTUnwrap(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "documentState",
            "trusted": false,
            "hasVisiblePasswordField": false
        ]))
        XCTAssertEqual(state.hasVisiblePasswordField, false)

        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "documentState",
            "hasVisiblePasswordField": false,
            "username": "unexpected"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 2,
            "event": "documentState",
            "hasVisiblePasswordField": false
        ]))
    }

    func testMessageContractRejectsUnboundedFormAndCredentialValues() {
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "focus",
            "trusted": true,
            "formID": String(repeating: "f", count: 257)
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "form-1",
            "username": String(repeating: "u", count: 1_025),
            "password": "secret",
            "passwordKind": "current"
        ]))
        XCTAssertNil(BrowserCredentialFormMessage(body: [
            "version": 1,
            "event": "submit",
            "trusted": true,
            "formID": "form-1",
            "username": "person",
            "password": String(repeating: "p", count: 16_385),
            "passwordKind": "current"
        ]))
    }

    func testCapturePolicyRequiresSecureFrameAndTopLevelOrigins() throws {
        let secure = try XCTUnwrap(CredentialOrigin(url: URL(string: "https://example.com/login")!))
        let insecure = try XCTUnwrap(CredentialOrigin(url: URL(string: "http://example.com/login")!))

        XCTAssertTrue(BrowserCredentialCapturePolicy.accepts(frameOrigin: secure, topLevelOrigin: secure))
        XCTAssertFalse(BrowserCredentialCapturePolicy.accepts(frameOrigin: insecure, topLevelOrigin: secure))
        XCTAssertFalse(BrowserCredentialCapturePolicy.accepts(frameOrigin: secure, topLevelOrigin: insecure))
        XCTAssertTrue(BrowserCredentialCapturePolicy.offersSavedCredentials(for: .current))
        XCTAssertFalse(BrowserCredentialCapturePolicy.offersSavedCredentials(for: .new))
    }

    func testMultiStepUsernameHintRequiresExactOriginsAndExpires() throws {
        let loginOrigin = try XCTUnwrap(CredentialOrigin(
            url: URL(string: "https://accounts.example.com/start")!
        ))
        let otherOrigin = try XCTUnwrap(CredentialOrigin(
            url: URL(string: "https://embedded.example.com/password")!
        ))
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let hint = BrowserCredentialUsernameHint(
            origin: loginOrigin,
            topLevelOrigin: loginOrigin,
            username: "person@example.com",
            capturedAt: capturedAt
        )

        XCTAssertEqual(
            BrowserCredentialCapturePolicy.username(
                from: hint,
                frameOrigin: loginOrigin,
                topLevelOrigin: loginOrigin,
                now: capturedAt.addingTimeInterval(1)
            ),
            "person@example.com"
        )
        XCTAssertNil(BrowserCredentialCapturePolicy.username(
            from: hint,
            frameOrigin: otherOrigin,
            topLevelOrigin: loginOrigin,
            now: capturedAt.addingTimeInterval(1)
        ))
        XCTAssertNil(BrowserCredentialCapturePolicy.username(
            from: hint,
            frameOrigin: loginOrigin,
            topLevelOrigin: otherOrigin,
            now: capturedAt.addingTimeInterval(1)
        ))
        XCTAssertNil(BrowserCredentialCapturePolicy.username(
            from: hint,
            frameOrigin: loginOrigin,
            topLevelOrigin: loginOrigin,
            now: capturedAt.addingTimeInterval(
                BrowserCredentialCapturePolicy.usernameHintLifetime + 1
            )
        ))
    }

    func testSaveOfferRequiresPasswordFieldToDisappearBeforeCandidateExpires() throws {
        let origin = try XCTUnwrap(CredentialOrigin(url: URL(string: "https://example.com/login")!))
        let submittedAt = Date(timeIntervalSince1970: 1_000)
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
        )

        XCTAssertFalse(BrowserCredentialCapturePolicy.shouldOfferSave(
            candidate: candidate,
            hasVisiblePasswordField: true,
            now: submittedAt.addingTimeInterval(1)
        ))
        XCTAssertTrue(BrowserCredentialCapturePolicy.shouldOfferSave(
            candidate: candidate,
            hasVisiblePasswordField: false,
            now: submittedAt.addingTimeInterval(1)
        ))
        XCTAssertFalse(BrowserCredentialCapturePolicy.shouldOfferSave(
            candidate: candidate,
            hasVisiblePasswordField: false,
            now: submittedAt.addingTimeInterval(BrowserCredentialCapturePolicy.candidateLifetime + 1)
        ))
        XCTAssertFalse(candidate.description.contains("secret"))
    }

    func testSavePromptModelMovesFromCreateToSavedAndSuppressesTheIdenticalCandidate() async throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.session.spaces.first)
        let submittedAt = Date(timeIntervalSince1970: 2_000)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
        )
        let model = BrowserCredentialSavePromptModel()

        await model.prepare(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        XCTAssertEqual(model.phase, .create)

        await model.commit(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        XCTAssertEqual(model.phase, .saved(.created))

        let repeatedModel = BrowserCredentialSavePromptModel()
        await repeatedModel.prepare(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        XCTAssertEqual(repeatedModel.phase, .alreadyStored)
    }

    func testSystemPasswordOfferRunsOnlyAfterCrestSaveAndRetriesWithoutDuplicatingIt() async throws {
        let store = BrowserStore(
            session: .preview,
            persistence: InMemoryBrowserSessionPersistence(),
            credentialVault: InMemoryCredentialVault()
        )
        let work = try XCTUnwrap(store.session.spaces.first)
        let submittedAt = Date(timeIntervalSince1970: 2_100)
        let origin = try XCTUnwrap(
            CredentialOrigin(url: try XCTUnwrap(URL(string: "https://accounts.crest.test/login")))
        )
        let candidate = BrowserCredentialSaveCandidate(
            id: UUID(),
            origin: origin,
            topLevelOrigin: origin,
            username: "person@example.com",
            password: "secret",
            passwordKind: .current,
            isCrossOriginFrame: false,
            submittedAt: submittedAt
        )
        let model = BrowserCredentialSavePromptModel()
        var offerCount = 0

        await model.offerToSystemPasswords {
            offerCount += 1
        }
        XCTAssertEqual(offerCount, 0)
        XCTAssertEqual(model.systemPasswordOfferPhase, .notRequested)

        await model.prepare(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        await model.commit(
            candidate: candidate,
            in: work.id,
            browser: store,
            now: submittedAt
        )
        await model.offerToSystemPasswords {
            offerCount += 1
            throw TestSystemPasswordOfferError.rejected
        }

        XCTAssertEqual(model.phase, .saved(.created))
        XCTAssertEqual(model.systemPasswordOfferPhase, .failed)
        XCTAssertEqual(offerCount, 1)
        var savedDescriptors = try await store.savedCredentialDescriptors(in: work.id)
        XCTAssertEqual(savedDescriptors.count, 1)

        await model.offerToSystemPasswords {
            offerCount += 1
        }

        XCTAssertEqual(model.phase, .saved(.created))
        XCTAssertEqual(model.systemPasswordOfferPhase, .completed)
        XCTAssertEqual(offerCount, 2)
        savedDescriptors = try await store.savedCredentialDescriptors(in: work.id)
        XCTAssertEqual(savedDescriptors.count, 1)
    }

    func testCredentialContentBridgeUsesABoundedIsolatedMessageContract() {
        let source = BrowserCredentialContentBridge.source

        XCTAssertTrue(source.contains("version: 1"))
        XCTAssertTrue(source.contains("MutationObserver"))
        XCTAssertTrue(source.contains("event.isTrusted"))
        XCTAssertTrue(source.contains("event: \"username\""))
        XCTAssertTrue(source.contains("event.composedPath"))
        XCTAssertTrue(source.contains("target instanceof Element"))
        XCTAssertTrue(source.contains("new WeakRef(root)"))
        XCTAssertTrue(source.contains("__crestCredentialBridge"))
        XCTAssertFalse(source.contains("localStorage"))
        XCTAssertFalse(source.contains("console."))
        XCTAssertFalse(source.contains("setInterval"))
    }

    func testContentBridgeInstallsAtDocumentStartInEveryFrame() {
        let controller = WKUserContentController()
        _ = BrowserCredentialContentBridge.install(in: controller, receive: { _ in })
        let script = controller.userScripts.last

        XCTAssertEqual(script?.injectionTime, .atDocumentStart)
        XCTAssertEqual(script?.isForMainFrameOnly, false)
    }

    func testContentBridgeRunsInsideASandboxedSubframeWithoutTreatingItAsMainFrame() async throws {
        let frameStatesExpectation = expectation(description: "main and sandboxed frame states")
        frameStatesExpectation.expectedFulfillmentCount = 2
        frameStatesExpectation.assertForOverFulfill = false
        var frameStates: [(
            isMainFrame: Bool,
            hasPassword: Bool,
            securityProtocol: String,
            securityHost: String
        )] = []

        _ = try await credentialBridgeWebView(html: """
        <!doctype html>
        <iframe sandbox="allow-forms allow-scripts" srcdoc="
          <style>input { width: 220px; height: 32px; }</style>
          <input type='password' autocomplete='current-password'>
        "></iframe>
        """) { scriptMessage in
            guard let message = BrowserCredentialFormMessage(body: scriptMessage.body),
                  message.event == .documentState,
                  let hasPassword = message.hasVisiblePasswordField else { return }
            frameStates.append((
                scriptMessage.frameInfo.isMainFrame,
                hasPassword,
                scriptMessage.frameInfo.securityOrigin.protocol,
                scriptMessage.frameInfo.securityOrigin.host
            ))
            if frameStates.count <= 2 {
                frameStatesExpectation.fulfill()
            }
        }

        await fulfillment(of: [frameStatesExpectation], timeout: 1)
        XCTAssertTrue(frameStates.contains { $0.isMainFrame && !$0.hasPassword })
        XCTAssertTrue(frameStates.contains { !$0.isMainFrame && $0.hasPassword })
        let sandboxedFrame = try XCTUnwrap(frameStates.first { !$0.isMainFrame })
        XCTAssertTrue(
            sandboxedFrame.securityProtocol.isEmpty
                || sandboxedFrame.securityHost.isEmpty
                || sandboxedFrame.securityProtocol == "about",
            "Expected an opaque sandbox origin, got \(sandboxedFrame.securityProtocol)://\(sandboxedFrame.securityHost)"
        )
    }

    func testIsolatedBridgeEmitsSeparateUsernameAndPasswordOnlySteps() async throws {
        let usernameExpectation = expectation(description: "username step")
        var usernameMessage: BrowserCredentialFormMessage?
        let usernameWebView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="username-step">
          <input autocomplete="username" value="person@example.com">
          <button type="submit">Next</button>
        </form>
        """) { scriptMessage in
            guard let message = BrowserCredentialFormMessage(body: scriptMessage.body),
                  message.event == .username else { return }
            usernameMessage = message
            usernameExpectation.fulfill()
        }
        let didCaptureUsername = try await captureForTesting("#username-step", in: usernameWebView)
        XCTAssertTrue(didCaptureUsername)
        await fulfillment(of: [usernameExpectation], timeout: 1)
        XCTAssertEqual(usernameMessage?.username, "person@example.com")
        XCTAssertNil(usernameMessage?.password)

        let passwordExpectation = expectation(description: "password-only step")
        var passwordMessage: BrowserCredentialFormMessage?
        let passwordWebView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="password-step">
          <input type="password" autocomplete="current-password" value="secret">
          <button type="submit">Sign In</button>
        </form>
        """) { scriptMessage in
            guard let message = BrowserCredentialFormMessage(body: scriptMessage.body),
                  message.event == .submit else { return }
            passwordMessage = message
            passwordExpectation.fulfill()
        }
        let didCapturePassword = try await captureForTesting("#password-step", in: passwordWebView)
        XCTAssertTrue(didCapturePassword)
        await fulfillment(of: [passwordExpectation], timeout: 1)
        XCTAssertNil(passwordMessage?.username)
        XCTAssertEqual(passwordMessage?.password, "secret")
        XCTAssertEqual(passwordMessage?.passwordKind, .current)
    }

    func testIsolatedBridgeReportsSPASuccessAfterThePasswordFormDisappears() async throws {
        let successExpectation = expectation(description: "SPA password form disappeared")
        let webView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="spa-login">
          <input autocomplete="username" value="person@example.com">
          <input type="password" autocomplete="current-password" value="secret">
          <button type="button">Sign In</button>
        </form>
        """) { scriptMessage in
            guard let message = BrowserCredentialFormMessage(body: scriptMessage.body),
                  message.event == .documentState,
                  message.hasVisiblePasswordField == false else { return }
            successExpectation.fulfill()
        }
        let didCapture = try await captureForTesting("#spa-login", in: webView)
        XCTAssertTrue(didCapture)
        _ = try await webView.callAsyncJavaScript(
            "document.querySelector('#spa-login').remove(); return true;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        await fulfillment(of: [successExpectation], timeout: 1)
    }

    func testIsolatedBridgeClassifiesAndFillsAnOrdinaryLoginForm() async throws {
        let webView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="login">
          <input id="login-user" autocomplete="username" value="person@example.com">
          <input id="login-password" type="password" autocomplete="current-password" value="old-secret">
        </form>
        """)

        let inspectionResult = try await inspect("#login", in: webView)
        let inspection = try XCTUnwrap(inspectionResult)
        let pageWorldBridgeVisibility = try await webView.callAsyncJavaScript(
            "return typeof globalThis.__crestCredentialBridge;",
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        XCTAssertEqual(pageWorldBridgeVisibility as? String, "undefined")
        XCTAssertEqual(inspection["username"] as? String, "person@example.com")
        XCTAssertEqual(inspection["passwordKind"] as? String, "current")
        XCTAssertEqual(inspection["passwordFieldID"] as? String, "login-password")
        XCTAssertEqual(inspection["passwordFieldCount"] as? Int, 1)

        let formID = try XCTUnwrap(inspection["formID"] as? String)
        let didFill = try await fill(
            formID: formID,
            username: "filled@example.com",
            password: "filled-secret",
            in: webView
        )
        XCTAssertTrue(didFill)
        let pageValues = try await pageJSON(
            """
            return JSON.stringify({
              username: document.querySelector('#login-user').value,
              password: document.querySelector('#login-password').value
            });
            """,
            in: webView
        )
        XCTAssertEqual(pageValues["username"] as? String, "filled@example.com")
        XCTAssertEqual(pageValues["password"] as? String, "filled-secret")
    }

    func testIsolatedBridgeSelectsMatchingNewPasswordAndRejectsAMismatch() async throws {
        let matchingWebView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="change-password">
          <input id="account" autocomplete="username" value="person@example.com">
          <input id="current" type="password" autocomplete="current-password" value="old-secret">
          <input id="new-password" type="password" autocomplete="new-password" value="next-secret">
          <input id="confirm-password" type="password" autocomplete="new-password" value="next-secret">
        </form>
        """)
        let matchingResult = try await inspect("#change-password", in: matchingWebView)
        let matching = try XCTUnwrap(matchingResult)
        XCTAssertEqual(matching["passwordKind"] as? String, "new")
        XCTAssertEqual(matching["passwordFieldID"] as? String, "new-password")
        XCTAssertEqual(matching["passwordFieldCount"] as? Int, 3)
        XCTAssertEqual(matching["passwordLength"] as? Int, 11)

        let mismatchingWebView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="signup">
          <input autocomplete="username" value="person@example.com">
          <input type="password" autocomplete="new-password" value="one-secret">
          <input type="password" autocomplete="new-password" value="different-secret">
        </form>
        """)
        let mismatchResult = try await inspect("#signup", in: mismatchingWebView)
        XCTAssertNil(mismatchResult)
    }

    func testIsolatedBridgeFillsOnlyTheExactNewAndConfirmationPasswordFields() async throws {
        let webView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <form id="change-password">
          <input id="account" autocomplete="username" value="person@example.com">
          <input id="current" type="password" autocomplete="current-password" value="current-secret">
          <input id="new" type="password" autocomplete="new-password">
          <input id="confirm" type="password" autocomplete="new-password">
        </form>
        """)

        let inspectionResult = try await inspect("#change-password", in: webView)
        let inspection = try XCTUnwrap(inspectionResult)
        XCTAssertEqual(inspection["passwordKind"] as? String, "new")
        let formID = try XCTUnwrap(inspection["formID"] as? String)

        let didFill = try await fillGenerated(
            formID: formID,
            password: "Generated-Strong_42!",
            in: webView
        )
        XCTAssertTrue(didFill)

        let values = try await pageJSON(
            """
            const form = document.querySelector('#change-password');
            return JSON.stringify({
              username: form.querySelector('#account').value,
              current: form.querySelector('#current').value,
              newPassword: form.querySelector('#new').value,
              confirmation: form.querySelector('#confirm').value
            });
            """,
            in: webView
        )
        XCTAssertEqual(values["username"] as? String, "person@example.com")
        XCTAssertEqual(values["current"] as? String, "current-secret")
        XCTAssertEqual(values["newPassword"] as? String, "Generated-Strong_42!")
        XCTAssertEqual(values["confirmation"] as? String, "Generated-Strong_42!")
    }

    func testIsolatedBridgeRejectsAContainerSpanningMultipleCredentialForms() async throws {
        let submitExpectation = expectation(description: "ambiguous container submission")
        submitExpectation.isInverted = true
        let webView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <main id="accounts">
          <form id="primary-account">
            <input autocomplete="username" value="primary@example.com">
            <input type="password" autocomplete="current-password" value="primary-secret">
          </form>
          <form id="secondary-account">
            <input autocomplete="username" value="secondary@example.com">
            <input type="password" autocomplete="current-password" value="secondary-secret">
          </form>
          <button type="button">Continue</button>
        </main>
        """) { scriptMessage in
            guard let message = BrowserCredentialFormMessage(body: scriptMessage.body),
                  message.event == .submit else { return }
            submitExpectation.fulfill()
        }

        let ambiguousInspection = try await inspect("#accounts", in: webView)
        XCTAssertNil(
            ambiguousInspection,
            "A container spanning independent forms must not guess which account was submitted."
        )
        let didCaptureAmbiguousContainer = try await captureForTesting("#accounts", in: webView)
        XCTAssertTrue(didCaptureAmbiguousContainer)
        await fulfillment(of: [submitExpectation], timeout: 0.2)

        let exactInspectionResult = try await inspect("#primary-account", in: webView)
        let exactInspection = try XCTUnwrap(exactInspectionResult)
        XCTAssertEqual(exactInspection["username"] as? String, "primary@example.com")
        XCTAssertEqual(exactInspection["passwordKind"] as? String, "current")
    }

    func testIsolatedBridgeClassifiesAndFillsAnOpenShadowRootLogin() async throws {
        let webView = try await credentialBridgeWebView(html: """
        <!doctype html>
        <div id="shadow-host"></div>
        <script>
          const root = document.querySelector('#shadow-host').attachShadow({ mode: 'open' });
          root.innerHTML = `
            <style>input { display: block; width: 220px; height: 32px; }</style>
            <input id="shadow-user" autocomplete="username" value="shadow@example.com">
            <input id="shadow-password" type="password" autocomplete="current-password" value="old-shadow-secret">
          `;
        </script>
        """)

        let inspectionResult = try await inspect("#shadow-host", in: webView)
        let inspection = try XCTUnwrap(inspectionResult)
        XCTAssertEqual(inspection["username"] as? String, "shadow@example.com")
        XCTAssertEqual(inspection["passwordKind"] as? String, "current")
        XCTAssertEqual(inspection["passwordFieldID"] as? String, "shadow-password")

        let formID = try XCTUnwrap(inspection["formID"] as? String)
        let didFill = try await fill(
            formID: formID,
            username: "filled-shadow@example.com",
            password: "filled-shadow-secret",
            in: webView
        )
        XCTAssertTrue(didFill)
        let pageValues = try await pageJSON(
            """
            const root = document.querySelector('#shadow-host').shadowRoot;
            return JSON.stringify({
              username: root.querySelector('#shadow-user').value,
              password: root.querySelector('#shadow-password').value
            });
            """,
            in: webView
        )
        XCTAssertEqual(pageValues["username"] as? String, "filled-shadow@example.com")
        XCTAssertEqual(pageValues["password"] as? String, "filled-shadow-secret")
    }

    func testOlderSessionsDecodeWithSafeCredentialPreferenceDefaults() throws {
        let encoded = try JSONEncoder().encode(BrowserSession.preview)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        for index in spaces.indices {
            spaces[index]["credentialPreferences"] = nil
        }
        root["spaces"] = spaces
        let legacyData = try JSONSerialization.data(withJSONObject: root)
        let decoded = try JSONDecoder().decode(BrowserSession.self, from: legacyData)

        XCTAssertTrue(decoded.spaces.allSatisfy {
            $0.credentialPreferences == .default
        })
    }

    func testOlderCredentialPreferencesEnableTheManagerByDefault() throws {
        let encoded = try JSONEncoder().encode(BrowserSession.preview)
        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var spaces = try XCTUnwrap(root["spaces"] as? [[String: Any]])
        for index in spaces.indices {
            var preferences = try XCTUnwrap(
                spaces[index]["credentialPreferences"] as? [String: Any]
            )
            preferences.removeValue(forKey: "isEnabled")
            spaces[index]["credentialPreferences"] = preferences
        }
        root["spaces"] = spaces

        let decoded = try JSONDecoder().decode(
            BrowserSession.self,
            from: JSONSerialization.data(withJSONObject: root)
        )

        XCTAssertTrue(decoded.spaces.allSatisfy {
            $0.credentialPreferences.isEnabled
        })
    }

    private func credentialBridgeWebView(
        html: String,
        receive: @escaping @MainActor (WKScriptMessage) -> Void = { _ in }
    ) async throws -> WKWebView {
        let configuration = WKWebViewConfiguration()
        _ = BrowserCredentialContentBridge.install(
            in: configuration.userContentController,
            receive: receive
        )
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let waiter = CredentialBridgeNavigationWaiter(webView: webView)
        try await waiter.load(
            simulatedRequest: URLRequest(url: URL(string: "https://forms.crest.test/")!),
            responseHTML: html
        )
        return webView
    }

    private func inspect(_ selector: String, in webView: WKWebView) async throws -> [String: Any]? {
        let value = try await webView.callAsyncJavaScript(
            "return JSON.stringify(globalThis.__crestCredentialBridge?.inspectForTesting(selector) ?? null);",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        let json = try XCTUnwrap(value as? String)
        if json == "null" { return nil }
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func fill(
        formID: String,
        username: String,
        password: String,
        in webView: WKWebView
    ) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fill(formID, username, password) === true;",
            arguments: [
                "formID": formID,
                "username": username,
                "password": password
            ],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func fillGenerated(
        formID: String,
        password: String,
        in webView: WKWebView
    ) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.fillGenerated(formID, password) === true;",
            arguments: [
                "formID": formID,
                "password": password
            ],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func captureForTesting(_ selector: String, in webView: WKWebView) async throws -> Bool {
        let value = try await webView.callAsyncJavaScript(
            "return globalThis.__crestCredentialBridge?.captureForTesting(selector) === true;",
            arguments: ["selector": selector],
            in: nil,
            contentWorld: BrowserCredentialContentBridge.contentWorld
        )
        return try XCTUnwrap(value as? Bool)
    }

    private func pageJSON(_ script: String, in webView: WKWebView) async throws -> [String: Any] {
        let value = try await webView.callAsyncJavaScript(
            script,
            arguments: [:],
            in: nil,
            contentWorld: .page
        )
        let json = try XCTUnwrap(value as? String)
        let data = try XCTUnwrap(json.data(using: .utf8))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private enum TestSystemPasswordOfferError: Error {
    case rejected
}

@MainActor
private final class CredentialBridgeNavigationWaiter: NSObject, WKNavigationDelegate {
    private weak var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, any Error>?

    init(webView: WKWebView) {
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
    }

    func load(simulatedRequest request: URLRequest, responseHTML: String) async throws {
        guard let webView else { throw CredentialBridgeNavigationWaiterError.releasedWebView }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadSimulatedRequest(request, responseHTML: responseHTML)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation?,
        withError error: any Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

private enum CredentialBridgeNavigationWaiterError: Error {
    case releasedWebView
}
