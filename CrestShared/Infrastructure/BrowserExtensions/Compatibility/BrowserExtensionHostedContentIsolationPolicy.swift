import Foundation
import WebKit

/// A hosted extension document keeps its native extension controller for its
/// own origin and APIs, but must not use the controller's shared injected
/// content. That controller receives every extension's scripts and styles,
/// including scripts matching websites embedded by the panel.
///
/// WebKit's per-navigation content controller overrides the content provider
/// for each document without registering it with the extension controller.
/// Keeping it separate also excludes scripts registered after the panel opens.
@MainActor
enum BrowserExtensionHostedContentIsolationPolicy {
    private static let setter = NSSelectorFromString("_setUserContentController:")
    private typealias Setter = @convention(c) (AnyObject, Selector, WKUserContentController) -> Void

    static var isSupported: Bool { WKWebpagePreferences().responds(to: setter) }

    /// Use only the preferences WebKit supplies to the navigation delegate.
    /// They are a native copy preserving every policy. Configuration copies
    /// share their default preferences, which must never be mutated here.
    /// A missing SPI refuses the navigation instead of admitting shared scripts.
    static func apply(_ controller: WKUserContentController, to preferences: WKWebpagePreferences) -> Bool {
        guard preferences.responds(to: setter), let method = preferences.method(for: setter) else { return false }
        unsafeBitCast(method, to: Setter.self)(preferences, setter, controller)
        return true
    }
}
