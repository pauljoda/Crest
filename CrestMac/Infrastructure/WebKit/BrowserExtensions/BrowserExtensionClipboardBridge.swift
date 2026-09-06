import AppKit
import WebKit

/// A synchronous return path for legacy extension paste commands. The bearer
/// capability lives only in a package-private isolated-world script. Every read
/// rechecks the loaded context, owning controller, host access and current grant.
@MainActor
final class BrowserExtensionClipboardBridge {
    static let shared = BrowserExtensionClipboardBridge()
    nonisolated static let promptPrefix = "crest-extension-clipboard:"
    private struct Registration {
        weak var context: WKWebExtensionContext?
        let allowsRead: () -> Bool
    }
    private var registrations: [String: Registration] = [:]

    func register(token: String, context: WKWebExtensionContext, allowsRead: @escaping () -> Bool) {
        registrations = registrations.filter { $0.value.context != nil }
        registrations[token] = Registration(context: context, allowsRead: allowsRead)
    }

    func unregister(context: WKWebExtensionContext) {
        registrations = registrations.filter { $0.value.context != nil && $0.value.context !== context }
    }

    func hasReadPermission(context: WKWebExtensionContext) -> Bool {
        context.webExtensionController != nil
            && registrations.values.contains {
                $0.context === context && $0.allowsRead()
            }
    }

    func readText(context: WKWebExtensionContext) -> String? {
        guard hasReadPermission(context: context) else { return nil }
        return NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// Returns whether this is an internal prompt, including rejected requests.
    /// Never forward a capability or clipboard contents to page dialogs/debuggers.
    func handlePrompt(
        _ prompt: String, webView: WKWebView, frame: WKFrameInfo, reply: (String?) -> Void
    ) -> Bool {
        guard prompt.hasPrefix(Self.promptPrefix) else { return false }
        let token = String(prompt.dropFirst(Self.promptPrefix.count))
        guard let registration = registrations[token], let context = registration.context,
            let controller = context.webExtensionController,
            controller === webView.configuration.webExtensionController,
            registration.allowsRead(), let url = frame.request.url,
            frame.securityOrigin.protocol == url.scheme,
            frame.securityOrigin.host == url.host,
            context.hasAccess(to: url)
                || (url.scheme == context.baseURL.scheme && url.host == context.baseURL.host)
        else {
            reply(nil)
            return true
        }
        reply(NSPasteboard.general.string(forType: .string) ?? "")
        return true
    }
}
