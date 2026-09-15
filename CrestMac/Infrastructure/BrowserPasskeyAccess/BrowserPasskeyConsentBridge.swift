import AppKit
import WebKit

/// Requests macOS browser consent without handling credential material. WebKit
/// still validates the RP, performs authentication, and returns the credential.
@MainActor
final class BrowserPasskeyConsentBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let messageHandlerName = "crestPasskeyConsent"
    private let access: BrowserPasskeyAccessController
    private static var recoveryTask: Task<Void, Never>?

    init(access: BrowserPasskeyAccessController = .shared) {
        self.access = access
    }

    static func install(in controller: WKUserContentController) -> BrowserPasskeyConsentBridge {
        let bridge = BrowserPasskeyConsentBridge()
        controller.addScriptMessageHandler(bridge, contentWorld: .page, name: messageHandlerName)
        controller.addUserScript(
            WKUserScript(
                source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page
            ))
        return bridge
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) async -> (Any?, String?) {
        guard message.body as? String == "request",
            Self.allowsConsent(from: BrowserSiteOrigin(message.frameInfo.securityOrigin)),
            let webView = message.webView,
            let topOrigin = webView.url.flatMap(BrowserSiteOrigin.init(url:)),
            Self.allowsConsent(from: topOrigin),
            let window = webView.window,
            window.isVisible, NSApp.isActive
        else { return (false, nil) }

        access.refreshStatus()
        if access.status == .denied {
            if let recoveryTask = Self.recoveryTask {
                await recoveryTask.value
            } else {
                let task = Task { await BrowserDialogPresenter().recoverPasskeySystemAuthorization() }
                Self.recoveryTask = task
                await task.value
                Self.recoveryTask = nil
            }
            access.refreshStatus()
        }
        await access.requestAccess()
        // A denial remains a denial. The native API owns any security-key or
        // cross-device alternatives and its standards-defined error response.
        return (true, nil)
    }

    static func allowsConsent(from origin: BrowserSiteOrigin) -> Bool {
        if origin.scheme == "https" { return true }
        guard origin.scheme == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(origin.host)
    }

    static let source = #"""
        (() => {
          "use strict";
          if (!isSecureContext || typeof CredentialsContainer === "undefined") return;
          const prototype = CredentialsContainer.prototype;
          const marker = Symbol.for("crest.passkeyConsent");
          if (prototype[marker]) return;
          Object.defineProperty(prototype, marker, { value: true });
          const handler = webkit.messageHandlers.crestPasskeyConsent;
          for (const method of ["create", "get"]) {
            const native = prototype[method];
            if (typeof native !== "function") continue;
            Object.defineProperty(prototype, method, {
              configurable: true, writable: true,
              value: function(options) {
                const args = arguments;
                const policy = document.permissionsPolicy || document.featurePolicy;
                if (this !== navigator.credentials || !options?.publicKey
                    || options.mediation === "conditional" || options.mediation === "silent"
                    || options.signal?.aborted || !document.hasFocus()
                    || (policy?.allowsFeature && !policy.allowsFeature("publickey-credentials-" + method))) {
                  return Reflect.apply(native, this, args);
                }
                return handler.postMessage("request").then(ready => {
                  if (!ready) throw new DOMException("Passkey request is no longer active.", "NotAllowedError");
                  if (options.signal?.aborted) throw options.signal.reason;
                  return Reflect.apply(native, this, args);
                });
              }
            });
          }
        })();
        """#
}
