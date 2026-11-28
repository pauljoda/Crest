import AppKit
import WebKit
import XCTest

@testable import Crest

/// An agent signs in with a login the person saved in Crest Passwords only
/// where they let it, in a tab it may use, and only once they agree; Crest
/// fills the form itself, and nothing the agent reads afterwards holds the
/// password, even once the page shows the field as text.
@MainActor
final class BrowserAgentSignInTests: XCTestCase {
    // MARK: - Static Variables

    private static let username = "person@example.com"
    private static let password = "saved-agent-secret"
    private static let address = "https://login.crest.test/sign-in"
    private static let signInDocument = """
        <!doctype html>
        <style>input { display: block; width: 220px; height: 32px; }</style>
        <h1>Sign in</h1>
        <form>
          <input autocomplete="username">
          <input type="password" autocomplete="current-password">
          <button type="button">Sign In</button>
        </form>
        """
    private static let usernameStepDocument = """
        <!doctype html>
        <form>
          <input autocomplete="username">
          <button type="button">Next</button>
        </form>
        """

    // MARK: - Actions - Boundaries

    func testCrestFillsASavedLoginOnlyWhereThePersonLetsItAndAsksEachTime() async throws {
        let fixture = try BrowserAgentFixture()
        let browser = fixture.application.browser
        guard browser.credentialVault is InMemoryCredentialVault else {
            return XCTFail("The test must never reach the Keychain.")
        }
        let (tab, page, fields) = try await openSignInPage(fixture)
        let arguments: [String: AgentJSON] = ["tab": .string(tab.uuidString), "uid": .string(fields.password)]

        // Off until the person turns it on.
        await assertRefused(fixture, arguments, .signInOff)
        try fixture.core.send(SetAgentPasswordFill(fillsPasswords: true))
        // A page-world script could read a filled password.
        try fixture.core.send(SetAgentScripts(runsScripts: true))
        await assertRefused(fixture, arguments, .signInWithScripts)
        try fixture.core.send(SetAgentScripts(runsScripts: false))

        // A login another Space keeps is never offered.
        try browser.addSpace()
        let other = try XCTUnwrap(browser.shownSpace)
        let url = try XCTUnwrap(URL(string: Self.address))
        try await browser.saveCredential(
            username: Self.username, password: Self.password, for: url, in: other.id)
        await assertRefused(fixture, arguments, .noSavedLogin)
        try await browser.saveCredential(
            username: Self.username, password: Self.password, for: url, in: fixture.space.id)

        // A button is no field of the form.
        await assertRefused(fixture, ["tab": .string(tab.uuidString), "uid": .string(fields.button)], .notSignInField)

        // Crest Passwords off for the Space.
        var preferences = fixture.space.settings.credentialPreferences
        preferences.isEnabled = false
        browser.updateCredentialPreferences(preferences, in: fixture.space.id)
        await assertRefused(fixture, arguments, .passwordsOff)
        preferences.isEnabled = true
        browser.updateCredentialPreferences(preferences, in: fixture.space.id)

        // A locked Space and a private window are out of reach.
        browser.updateSpaceAccessPolicy(.deviceOwnerAuthentication, in: fixture.space.id)
        await assertRefused(fixture, arguments, .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: tab))))
        browser.unlockForTesting(fixture.space.value.seed)
        browser.updateSpaceAccessPolicy(.open, in: fixture.space.id)
        fixture.windows.openPrivateWindow()
        defer { fixture.application.closePrivateBrowsingWindow() }
        let privateTab = try XCTUnwrap(fixture.application.privateBrowser.shownTab)
        await assertRefused(
            fixture, ["tab": .string(privateTab.id.uuidString), "uid": .string(fields.password)],
            .rejected(.agentTabUnavailable(AgentTabUnavailable(tabID: privateTab.id))))
        XCTAssertTrue(fixture.answers.signIns.isEmpty, "Nothing out of bounds asks the person.")

        // The person is asked, naming the agent, the site and the login, and
        // may decline.
        fixture.answers.signsIn = false
        await assertRefused(fixture, arguments, .signInDeclined)
        let asked = try XCTUnwrap(fixture.answers.signIns.last)
        XCTAssertEqual(asked.agentName, "Test")
        XCTAssertEqual(asked.site, "login.crest.test")
        XCTAssertEqual(asked.logins.map(\.username), [Self.username])
        XCTAssertNil(page.credentialFillRequest, "A declined fill leaves no popup behind.")
        try await assertFields(of: page, hold: ["", ""])
    }

    // MARK: - Actions - Filling

    func testAFilledPasswordNeverReachesWhatTheAgentReads() async throws {
        let fixture = try BrowserAgentFixture()
        let browser = fixture.application.browser
        guard browser.credentialVault is InMemoryCredentialVault else {
            return XCTFail("The test must never reach the Keychain.")
        }
        let url = try XCTUnwrap(URL(string: Self.address))
        try await browser.saveCredential(
            username: Self.username, password: Self.password, for: url, in: fixture.space.id)
        try fixture.core.send(SetAgentPasswordFill(fillsPasswords: true))
        let (tab, page, fields) = try await openSignInPage(fixture)
        let reference: [String: AgentJSON] = ["tab": .string(tab.uuidString)]

        let filled = try await fixture.message(
            "fill_credential", ["tab": .string(tab.uuidString), "uid": .string(fields.username)])
        try await assertFields(of: page, hold: [Self.username, Self.password])
        XCTAssertEqual(fixture.answers.signIns.count, 1)
        XCTAssertNil(page.credentialFillRequest, "The fill leaves no popup behind.")
        let activity = try XCTUnwrap(
            fixture.core.state.agentSessions.first { $0.sessionID == fixture.sessionID }?.activity.last)
        XCTAssertEqual(activity.kind, .filledPassword)
        XCTAssertEqual(activity.subject, "login.crest.test")

        var read = [filled]
        read.append(try await fixture.message("take_snapshot", reference))
        // A "Show password" button turns the field into a text field.
        _ = try await page.webView.evaluateJavaScript("document.querySelector('input[type=password]').type = 'text'")
        read.append(try await fixture.message("take_snapshot", reference))
        read.append(try await fixture.message("read_page_text", reference))
        for text in read { XCTAssertFalse(text.contains(Self.password), text) }
        XCTAssertFalse(filled.contains(Self.username))
        // The field reads as a password before and after it shows as text.
        XCTAssertTrue(read[1].contains("[password]"), read[1])
        XCTAssertTrue(read[2].contains("[password]"), read[2])

        // A login filled on a username step fills no password step after it
        // by itself: the person is asked again.
        let loaded = page.completedNavigationCount
        page.webView.loadSimulatedRequest(URLRequest(url: url), responseHTML: Self.usernameStepDocument)
        try await waitUntil { page.completedNavigationCount > loaded }
        let step = try await fixture.message("take_snapshot", reference)
        let username = try Self.uid(in: step) { $0.contains("- textbox") }
        _ = try await fixture.message("fill_credential", reference.merging(["uid": .string(username)]) { $1 })
        try await assertFields(of: page, hold: [Self.username])
        XCTAssertEqual(fixture.answers.signIns.count, 2)
        let origin = try XCTUnwrap(CredentialOrigin(url: url))
        XCTAssertFalse(page.credentialState.awaitsPasswordStep(at: origin, now: .now))
    }

    // MARK: - Actions - Helpers

    /// A tab of the fixture's Space showing a sign-in form, its page, and the
    /// uids of the form's username field, password field and button.
    private func openSignInPage(_ fixture: BrowserAgentFixture) async throws
        -> (UUID, BrowserPage, (username: String, password: String, button: String))
    {
        let opening = try await fixture.invoke(
            "open_tab", ["space": .string(fixture.space.id.uuidString), "url": .string(Self.address)])
        let tab = try XCTUnwrap(opening["tab"]?["id"]?.string.flatMap(UUID.init(uuidString:)))
        let page = try fixture.page(for: tab)
        let loaded = page.completedNavigationCount
        page.webView.loadSimulatedRequest(
            URLRequest(url: try XCTUnwrap(URL(string: Self.address))), responseHTML: Self.signInDocument)
        try await waitUntil { page.completedNavigationCount > loaded && page.live.url == Self.address }
        let outline = try await fixture.message("take_snapshot", ["tab": .string(tab.uuidString)])
        let username = try Self.uid(in: outline) { $0.contains("- textbox") && !$0.contains("[password]") }
        let password = try Self.uid(in: outline) { $0.contains("- textbox") && $0.contains("[password]") }
        let button = try Self.uid(in: outline) { $0.contains("- button") }
        return (tab, page, (username, password, button))
    }

    /// The uid of the first element of `outline` whose line `matching` picks.
    private static func uid(in outline: String, _ matching: (String) -> Bool) throws -> String {
        let line = try XCTUnwrap(outline.split(separator: "\n").map(String.init).first(where: matching), outline)
        return String(try XCTUnwrap(line.firstMatch(of: /\[uid=(e\d+)\]/), line).1)
    }

    /// Fails the test unless `fill_credential` refuses `arguments` with
    /// `expected`.
    private func assertRefused(
        _ fixture: BrowserAgentFixture, _ arguments: [String: AgentJSON], _ expected: BrowserAgentFailure,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            let answer = try await fixture.message("fill_credential", arguments)
            XCTFail("fill_credential should refuse, but answered: \(answer)", file: file, line: line)
        } catch let failure as BrowserAgentFailure {
            XCTAssertEqual(failure.message, expected.message, file: file, line: line)
        } catch {
            XCTFail("fill_credential failed unexpectedly: \(error)", file: file, line: line)
        }
    }

    /// Fails the test unless the form's username and password fields hold
    /// `values`, as the page reads them.
    private func assertFields(of page: BrowserPage, hold values: [String], line: UInt = #line) async throws {
        let held =
            try await page.webView.evaluateJavaScript(
                "[...document.querySelectorAll('form input')].map((input) => input.value)") as? [String]
        XCTAssertEqual(held, values, line: line)
    }
}
