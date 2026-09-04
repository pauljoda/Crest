import Foundation
import WebKit

/// Keeps a framed website's own content security policy in force inside the
/// extension documents Crest hosts.
///
/// WebKit stamps an extension's manifest CSP mode on the *page*: WebCore reads
/// `page->contentSecurityPolicyModeForExtension()` into every document's policy
/// in that web view, cross-origin frames included, and Manifest V3 mode then
/// restricts `script-src` to `'self'` and refuses nonces, hashes and remote
/// hosts. Chrome scopes that policy to extension-origin documents only. The
/// visible failure: Claude's side panel frames `https://claude.ai/cic/new`,
/// whose scripts carry claude.ai's own nonces and load from Anthropic's asset
/// host, and WebKit refuses every one of them — a blank frame.
///
/// Crest clears the mode on the configuration copy it receives for its own
/// extension documents (side panel, offscreen documents, extension pages
/// opened as tabs), so each document in those web views is governed by its own
/// policy exactly as a web page would be. The trade-off, accepted for
/// extensions within their Space: WebKit no longer enforces the manifest's
/// Manifest V3 restrictions on the extension's own page in those web views.
/// WebKit-owned popups are untouched. The mode is reached through its private
/// setter's C entry point because KVC cannot resolve an underscore-prefixed
/// custom setter, and absence of the SPI leaves the configuration alone.
enum BrowserExtensionHostedPageConfigurationPolicy {
    /// `_WKContentSecurityPolicyModeForExtension` raw values.
    enum Mode: UInt {
        case none = 0
        case manifestV2 = 1
        case manifestV3 = 2
    }

    private static let getterSelector = NSSelectorFromString("_contentSecurityPolicyModeForExtension")
    private static let setterSelector = NSSelectorFromString("_setContentSecurityPolicyModeForExtension:")
    private typealias Getter = @convention(c) (AnyObject, Selector) -> UInt
    private typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void

    static func isSupported(by configuration: WKWebViewConfiguration) -> Bool {
        configuration.responds(to: getterSelector) && configuration.responds(to: setterSelector)
    }

    static func extensionContentSecurityPolicyMode(of configuration: WKWebViewConfiguration) -> Mode? {
        guard isSupported(by: configuration), let method = configuration.method(for: getterSelector) else { return nil }
        return Mode(rawValue: unsafeBitCast(method, to: Getter.self)(configuration, getterSelector))
    }

    /// Sets the mode; `false` when the SPI is unavailable.
    @discardableResult
    static func setExtensionContentSecurityPolicyMode(_ mode: Mode, on configuration: WKWebViewConfiguration)
        -> Bool
    {
        guard isSupported(by: configuration), let method = configuration.method(for: setterSelector) else {
            return false
        }
        unsafeBitCast(method, to: Setter.self)(configuration, setterSelector, mode.rawValue)
        return true
    }

    /// Lets every document in a Crest-hosted extension web view keep its own
    /// content security policy. `false` when the SPI is unavailable.
    @discardableResult
    static func clearExtensionContentSecurityPolicyMode(on configuration: WKWebViewConfiguration) -> Bool {
        setExtensionContentSecurityPolicyMode(.none, on: configuration)
    }
}
