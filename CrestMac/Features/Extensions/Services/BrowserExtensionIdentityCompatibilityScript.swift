/// Included inside the compatibility runtime's lexical scope, after the
/// sidebar, tab-group, and debugger fragments. It reuses the runtime's own
/// `requestCapability`, `callbackOrPromise`, `rejectCallbackOrPromise`,
/// `extensionID`, and `declaredManifest`; the matrix owns publication, so
/// defining this object never makes an unavailable API visible.
///
/// Two halves live here, and they fail in opposite directions on purpose.
/// `getRedirectURL` and `launchWebAuthFlow` are the portable half — an
/// authorization flow against any provider — and Crest implements them. The
/// `getAuthToken` family is Google-account plumbing tied to Chrome's own sign-in
/// state, which Crest has none of, so those members answer the way a Chrome
/// profile with no Google account answers rather than pretending to work.
enum BrowserExtensionIdentityCompatibilityScript {
    static let source = #"""
        // Chrome watches its own web view for a navigation to
        // `https://<runtime id>.chromiumapp.org/*`; it owns no more of that
        // domain than Crest does. `runtime.id` is read live because a verified
        // Chrome Web Store package runs at its real store origin, which is the
        // `[a-p]{32}` host the provider has on file. A package from any other
        // source keeps Crest's per-Space host, so the round trip still works
        // and a provider that validates the redirect host will refuse it —
        // exactly as it refuses an unpacked extension in Chrome.
        const identityRuntimeID = () => {
            for (const root of [globalThis.browser, globalThis.chrome]) {
                let id;
                try { id = root?.runtime?.id; } catch {}
                if (typeof id === "string" && id.length > 0) return id;
            }
            return extensionID;
        };
        const identityRedirectBase = () => `https://${identityRuntimeID()}.chromiumapp.org/`;
        const identityAccountStatus = Object.freeze({SYNC: "SYNC", ANY: "ANY"});
        // Chrome resolves `path` against the redirect base, so a leading slash
        // is optional and an absolute URL replaces the base outright. Crest
        // derives the origin it watches for from the loaded context itself, so
        // a package that hands itself a foreign redirect simply never matches.
        const identityRedirectURL = (path) => {
            const base = identityRedirectBase();
            if (path === undefined || path === null) return base;
            try { return new URL(String(path), base).href; } catch { return base; }
        };
        const identityDetails = (args) => {
            const value = args[0];
            if (value === undefined || typeof value === "function") return {};
            if (!value || typeof value !== "object" || Array.isArray(value)) {
                throw new Error("Identity options must be an object.");
            }
            return value;
        };
        const identityProperty = (options, name, type) => {
            if (options[name] === undefined) return undefined;
            if (typeof options[name] !== type) throw new Error(`${name} must be ${type}.`);
            return options[name];
        };
        // Chrome's ceiling and default for a non-interactive flow. A request
        // for longer is a request to keep an invisible web view alive.
        const identityMaximumTimeout = 60000;
        const identityWebAuthFlowPayload = (args) => {
            const options = identityDetails(args);
            if (options.url === undefined) throw new Error("Missing required property 'url'.");
            const url = identityProperty(options, "url", "string");
            let parsed;
            try { parsed = new URL(url); } catch {}
            if (!parsed || (parsed.protocol !== "https:" && parsed.protocol !== "http:")) {
                throw new Error("Authorization page could not be loaded.");
            }
            const interactive = identityProperty(options, "interactive", "boolean") ?? false;
            const abortOnLoad = identityProperty(options, "abortOnLoadForNonInteractive", "boolean") ?? true;
            const requested = identityProperty(options, "timeoutMsForNonInteractive", "number");
            const timeoutMs = requested === undefined || !Number.isFinite(requested)
                ? identityMaximumTimeout
                : Math.min(identityMaximumTimeout, Math.max(1, Math.floor(requested)));
            return {url: parsed.href, interactive, abortOnLoadForNonInteractive: abortOnLoad, timeoutMs};
        };
        // Signin state Crest cannot observe. The registry is real so a package
        // can add, remove, and re-check a listener the way Chrome lets it; what
        // Crest never does is invent an account change to deliver through it.
        const identitySignInListeners = new Set();
        const identityOnSignInChanged = Object.freeze({
            addListener(listener) { if (typeof listener === "function") identitySignInListeners.add(listener); },
            removeListener(listener) { identitySignInListeners.delete(listener); },
            hasListener(listener) { return identitySignInListeners.has(listener); },
            hasListeners() { return identitySignInListeners.size > 0; }
        });
        const identity = {
            AccountStatus: identityAccountStatus,
            getRedirectURL(path) { return identityRedirectURL(path); },
            launchWebAuthFlow(...args) {
                let payload;
                try { payload = identityWebAuthFlowPayload(args); }
                catch (error) { return rejectCallbackOrPromise(args, error.message); }
                return requestCapability(
                    "identity.launchWebAuthFlow",
                    payload,
                    args,
                    (response) => (typeof response?.url === "string" ? response.url : undefined)
                );
            },
            // Chrome's account list for a profile with no Google account. An
            // empty array is that answer, not a stub for one.
            getAccounts(...args) { return callbackOrPromise(args, []); },
            // Chrome returns empty strings when no Google account is signed in
            // or the `identity.email` permission is absent, which is every
            // Crest profile. This is Chrome's behaviour, not a placeholder.
            getProfileUserInfo(...args) { return callbackOrPromise(args, {email: "", id: ""}); },
            // Crest holds no Google OAuth2 token cache, so there is nothing to
            // mint. Chrome's own refusal text says which half of the contract
            // is missing: the manifest section, or the grant behind it.
            getAuthToken(...args) {
                const hasOAuth2 = declaredManifest?.oauth2 !== undefined && declaredManifest?.oauth2 !== null;
                return rejectCallbackOrPromise(
                    args,
                    hasOAuth2 ? "OAuth2 not granted or revoked." : "Invalid manifest: 'oauth2' section is missing."
                );
            },
            // Removing a token from an empty cache genuinely succeeds, and
            // clearing empty state genuinely clears it. Neither is a no-op
            // standing in for work Crest skipped.
            removeCachedAuthToken(...args) { return callbackOrPromise(args, undefined); },
            clearAllCachedAuthTokens(...args) { return callbackOrPromise(args, undefined); },
            onSignInChanged: identityOnSignInChanged
        };
        """#
}
