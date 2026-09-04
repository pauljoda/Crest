import WebKit
import XCTest

@testable import Crest

@MainActor
final class BrowserExtensionIdentityCompatibilityScriptTests: XCTestCase {
    /// The Claude extension reads `getRedirectURL()` while it builds the
    /// authorize URL, before anything can be awaited, and hands the result to
    /// claude.ai as `redirect_uri`. A different string there is a rejected
    /// authorization, not a degraded one.
    func testRedirectURLResolvesAgainstTheRuntimesOwnChromiumappOrigin() async throws {
        let result = try await evaluate(
            """
            return {
                base: identity.getRedirectURL(),
                undefinedPath: identity.getRedirectURL(undefined),
                bare: identity.getRedirectURL('cb'),
                rooted: identity.getRedirectURL('/cb'),
                nested: identity.getRedirectURL('oauth/done'),
                status: identity.AccountStatus,
                statusFrozen: Object.isFrozen(identity.AccountStatus),
                surface: Object.keys(identity).sort()
            };
            """)
        XCTAssertEqual(result["base"] as? String, "https://fixtureextensionid.chromiumapp.org/")
        XCTAssertEqual(result["undefinedPath"] as? String, "https://fixtureextensionid.chromiumapp.org/")
        XCTAssertEqual(result["bare"] as? String, "https://fixtureextensionid.chromiumapp.org/cb")
        XCTAssertEqual(result["rooted"] as? String, "https://fixtureextensionid.chromiumapp.org/cb")
        XCTAssertEqual(result["nested"] as? String, "https://fixtureextensionid.chromiumapp.org/oauth/done")
        XCTAssertEqual(result["status"] as? [String: String], ["SYNC": "SYNC", "ANY": "ANY"])
        XCTAssertEqual(result["statusFrozen"] as? Bool, true)
        XCTAssertEqual(
            result["surface"] as? [String],
            [
                "AccountStatus", "clearAllCachedAuthTokens", "getAccounts", "getAuthToken",
                "getProfileUserInfo", "getRedirectURL", "launchWebAuthFlow",
                "onSignInChanged", "removeCachedAuthToken",
            ])
    }

    /// A store package runs at its real Chrome origin, so the redirect host is
    /// the one the provider has on file. The fragment reads `runtime.id` live
    /// rather than trusting the id baked in at preparation.
    func testRedirectURLPrefersTheLiveRuntimeIdentifier() async throws {
        let result = try await evaluate(
            """
            globalThis.chrome = {runtime: {id: 'fcoeoabgfenejglbffodgkkbkcdhcgfn'}};
            return {live: identity.getRedirectURL('x')};
            """)
        XCTAssertEqual(
            result["live"] as? String,
            "https://fcoeoabgfenejglbffodgkkbkcdhcgfn.chromiumapp.org/x")
    }

    /// The exact envelope the Claude extension's silent re-auth produces, and
    /// the URL it expects back. `abortOnLoadForNonInteractive: false` with a
    /// 5s timeout is the shape a JavaScript-redirecting provider needs.
    func testLaunchWebAuthFlowSendsTheBrokerEnvelopeAndResolvesWithTheRedirectURL() async throws {
        let result = try await evaluate(
            """
            const resolved = await identity.launchWebAuthFlow({
                url: 'https://claude.ai/oauth/authorize?client_id=abc&prompt=none',
                interactive: false,
                abortOnLoadForNonInteractive: false,
                timeoutMsForNonInteractive: 5000
            });
            const defaulted = await identity.launchWebAuthFlow({url: 'https://example.com/auth'});
            const viaCallback = await new Promise(resolve => identity.launchWebAuthFlow(
                {url: 'https://example.com/auth', interactive: true}, resolve));
            return {resolved, defaulted, viaCallback, requests};
            """)
        XCTAssertEqual(
            result["resolved"] as? String,
            "https://fixtureextensionid.chromiumapp.org/?code=abc&state=xyz")
        XCTAssertEqual(
            result["defaulted"] as? String,
            "https://fixtureextensionid.chromiumapp.org/?code=abc&state=xyz")
        XCTAssertEqual(
            result["viaCallback"] as? String,
            "https://fixtureextensionid.chromiumapp.org/?code=abc&state=xyz")

        let requests = try XCTUnwrap(result["requests"] as? [[String: Any]])
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests[0]["api"] as? String, "identity.launchWebAuthFlow")
        XCTAssertEqual(
            requests[0]["url"] as? String,
            "https://claude.ai/oauth/authorize?client_id=abc&prompt=none")
        XCTAssertEqual(requests[0]["interactive"] as? Bool, false)
        XCTAssertEqual(requests[0]["abortOnLoadForNonInteractive"] as? Bool, false)
        XCTAssertEqual(requests[0]["timeoutMs"] as? Int, 5000)
        // Chrome's defaults, sent explicitly so the broker never has to guess.
        XCTAssertEqual(requests[1]["interactive"] as? Bool, false)
        XCTAssertEqual(requests[1]["abortOnLoadForNonInteractive"] as? Bool, true)
        XCTAssertEqual(requests[1]["timeoutMs"] as? Int, 60000)
        XCTAssertEqual(requests[2]["interactive"] as? Bool, true)
        // The broker never receives a redirect the extension chose.
        XCTAssertNil(requests[0]["redirectUri"])
        XCTAssertNil(requests[0]["redirectOrigin"])
    }

    /// A request that cannot be honoured is refused before the broker sees it,
    /// and an oversized non-interactive timeout is clamped rather than sent.
    func testInvalidDetailsRejectBeforeTheBrokerAndTimeoutsAreClamped() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            for (const call of [
                () => identity.launchWebAuthFlow({}),
                () => identity.launchWebAuthFlow({url: 42}),
                () => identity.launchWebAuthFlow({url: '/relative'}),
                () => identity.launchWebAuthFlow({url: 'ftp://example.com/'}),
                () => identity.launchWebAuthFlow({url: 'https://a.test/', interactive: 'yes'}),
                () => identity.launchWebAuthFlow({url: 'https://a.test/', timeoutMsForNonInteractive: 'soon'}),
                () => identity.launchWebAuthFlow([])
            ]) { try { await call(); } catch (error) { errors.push(error.message); } }
            const before = requests.length;
            await identity.launchWebAuthFlow({url: 'https://a.test/', timeoutMsForNonInteractive: 900000});
            await identity.launchWebAuthFlow({url: 'https://a.test/', timeoutMsForNonInteractive: -5});
            const lastError = await new Promise(resolve => identity.launchWebAuthFlow({}, () => resolve(lastErrorMessage)));
            return {errors, before, lastError, timeouts: requests.map(entry => entry.timeoutMs)};
            """)
        XCTAssertEqual(
            result["errors"] as? [String],
            [
                "Missing required property 'url'.",
                "url must be string.",
                "Authorization page could not be loaded.",
                "Authorization page could not be loaded.",
                "interactive must be boolean.",
                "timeoutMsForNonInteractive must be number.",
                "Identity options must be an object.",
            ])
        XCTAssertEqual(result["before"] as? Int, 0)
        XCTAssertEqual(result["timeouts"] as? [Int], [60000, 1])
        XCTAssertEqual(result["lastError"] as? String, "Missing required property 'url'.")
    }

    /// Chrome's three failure texts reach the extension unchanged in both the
    /// promise and the callback form. Packages branch on these strings.
    func testBrokerFailuresRelayChromesOwnText() async throws {
        let result = try await evaluate(
            """
            const errors = [], lastErrors = [];
            for (const failure of [
                'Authorization page could not be loaded.',
                'The user did not approve access.',
                'User interaction required.'
            ]) {
                failWith = failure;
                try { await identity.launchWebAuthFlow({url: 'https://a.test/'}); }
                catch (error) { errors.push(error.message); }
                await new Promise(resolve => identity.launchWebAuthFlow(
                    {url: 'https://a.test/'}, () => { lastErrors.push(lastErrorMessage); resolve(); }));
            }
            return {errors, lastErrors};
            """)
        let expected = [
            "Authorization page could not be loaded.",
            "The user did not approve access.",
            "User interaction required.",
        ]
        XCTAssertEqual(result["errors"] as? [String], expected)
        XCTAssertEqual(result["lastErrors"] as? [String], expected)
    }

    /// The Google-account half. Each of these is the answer a Chrome profile
    /// with no Google account gives — not a no-op reporting success for work
    /// that never happened.
    func testGoogleAccountMembersAnswerAsASignedOutChromeProfile() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            try { await identity.getAuthToken({interactive: false}); } catch (error) { errors.push(error.message); }
            const tokenLastError = await new Promise(resolve => identity.getAuthToken(() => resolve(lastErrorMessage)));
            return {
                errors,
                tokenLastError,
                accounts: await identity.getAccounts(),
                userInfo: await identity.getProfileUserInfo(),
                userInfoWithDetails: await identity.getProfileUserInfo({accountStatus: 'ANY'}),
                removed: await identity.removeCachedAuthToken({token: 'stale'}),
                cleared: await identity.clearAllCachedAuthTokens(),
                callbackAccounts: await new Promise(resolve => identity.getAccounts(resolve)),
                requests
            };
            """)
        XCTAssertEqual(result["errors"] as? [String], ["Invalid manifest: 'oauth2' section is missing."])
        XCTAssertEqual(result["tokenLastError"] as? String, "Invalid manifest: 'oauth2' section is missing.")
        XCTAssertEqual(result["accounts"] as? [String], [])
        XCTAssertEqual(result["callbackAccounts"] as? [String], [])
        XCTAssertEqual(result["userInfo"] as? [String: String], ["email": "", "id": ""])
        XCTAssertEqual(result["userInfoWithDetails"] as? [String: String], ["email": "", "id": ""])
        XCTAssertNil(result["removed"])
        XCTAssertNil(result["cleared"])
        // None of these reach the broker: Crest answers them locally.
        XCTAssertTrue((result["requests"] as? [Any])?.isEmpty == true)
    }

    /// A manifest that declares `oauth2` has the section Chrome needs and is
    /// still missing the grant, so the refusal names the other half.
    func testGetAuthTokenNamesTheMissingGrantWhenTheManifestDeclaresOAuth2() async throws {
        let result = try await evaluate(
            """
            const errors = [];
            try { await identity.getAuthToken(); } catch (error) { errors.push(error.message); }
            return {errors};
            """, manifest: "{oauth2: {client_id: 'abc.apps.googleusercontent.com', scopes: []}}")
        XCTAssertEqual(result["errors"] as? [String], ["OAuth2 not granted or revoked."])
    }

    /// Crest observes no Google sign-in state, so the event never fires. The
    /// registry behind it is real: a package cannot tell a refused
    /// registration from a Crest bug unless `hasListener` answers honestly.
    func testOnSignInChangedKeepsARealRegistryAndNeverFires() async throws {
        let result = try await evaluate(
            """
            const received = [];
            const listener = (account, signedIn) => received.push([account, signedIn]);
            identity.onSignInChanged.addListener(listener);
            identity.onSignInChanged.addListener('not a function');
            const added = identity.onSignInChanged.hasListener(listener);
            const any = identity.onSignInChanged.hasListeners();
            identity.onSignInChanged.removeListener(listener);
            return {
                added,
                any,
                afterRemove: identity.onSignInChanged.hasListener(listener),
                emptied: identity.onSignInChanged.hasListeners(),
                received,
                frozen: Object.isFrozen(identity.onSignInChanged)
            };
            """)
        XCTAssertEqual(result["added"] as? Bool, true)
        XCTAssertEqual(result["any"] as? Bool, true)
        XCTAssertEqual(result["afterRemove"] as? Bool, false)
        XCTAssertEqual(result["emptied"] as? Bool, false)
        XCTAssertEqual((result["received"] as? [Any])?.count, 0)
        XCTAssertEqual(result["frozen"] as? Bool, true)
    }

    private func evaluate(
        _ body: String, manifest: String = "{}"
    ) async throws -> [String: Any] {
        let script = """
            globalThis.chrome = undefined;
            globalThis.browser = undefined;
            const extensionID = 'fixtureextensionid';
            const declaredManifest = \(manifest);
            const requests = [];
            let failWith;
            let lastErrorMessage;
            const invokeCallbackWithLastError = (callback, message) => {
                lastErrorMessage = message;
                callback(undefined);
            };
            const callbackOrPromise = (args, value) => {
                const callback = args.at(-1);
                if (typeof callback === 'function') { queueMicrotask(() => callback(value)); return undefined; }
                return Promise.resolve(value);
            };
            const rejectCallbackOrPromise = (args, message) => {
                const callback = args.at(-1);
                if (typeof callback === 'function') {
                    queueMicrotask(() => invokeCallbackWithLastError(callback, message));
                    return undefined;
                }
                return Promise.reject(new Error(message));
            };
            const requestCapability = (api, payload, args, transform = value => value) => {
                requests.push({api, ...payload});
                const response = failWith
                    ? Promise.reject(new Error(failWith))
                    : Promise.resolve(transform({url: 'https://fixtureextensionid.chromiumapp.org/?code=abc&state=xyz'}));
                const callback = args.at(-1);
                if (typeof callback !== 'function') return response;
                response.then(value => callback(value), error => invokeCallbackWithLastError(callback, error.message));
                return undefined;
            };
            \(BrowserExtensionIdentityCompatibilityScript.source)
            return JSON.stringify(await (async () => { \(body) })());
            """
        let output = try await WKWebView().callAsyncJavaScript(
            script, arguments: [:], contentWorld: .page)
        let data = Data(try XCTUnwrap(output as? String).utf8)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
