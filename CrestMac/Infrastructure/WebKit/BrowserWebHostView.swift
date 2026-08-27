import AppKit
import WebKit
import os

struct BrowserWebFocusRestorationGate: Equatable {
    let browserChromeOwnsFocus: Bool
    let pageChromeOwnsFocus: Bool

    static let suppressed = BrowserWebFocusRestorationGate(
        browserChromeOwnsFocus: true,
        pageChromeOwnsFocus: false
    )

    var allowsWebPageFocus: Bool {
        !browserChromeOwnsFocus && !pageChromeOwnsFocus
    }
}

enum BrowserWebFocusRestorationCurrentOwner: Equatable {
    case neutral
    case webContent
    case departingWebContent
    case other
}

@MainActor
final class BrowserMenuTrackingMonitor {
    static let shared = BrowserMenuTrackingMonitor()

    private var observationTokens: [NSObjectProtocol] = []
    private var trackingDepth = 0

    var isTracking: Bool { trackingDepth > 0 }

    init(notificationCenter: NotificationCenter = .default) {
        observationTokens = [
            notificationCenter.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.trackingDepth += 1
                }
            },
            notificationCenter.addObserver(
                forName: NSMenu.didEndTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.trackingDepth = max(0, self.trackingDepth - 1)
                }
            },
        ]
    }
}

struct BrowserWebFocusRestorationPolicy {
    static func allowsRestoration(
        hasPendingCandidate: Bool,
        candidateBelongsToWebView: Bool,
        gate: BrowserWebFocusRestorationGate,
        windowIsKey: Bool,
        applicationIsActive: Bool,
        windowHasAttachedSheet: Bool,
        menuIsTracking: Bool,
        accessibilityOwnsFocus: Bool,
        currentOwner: BrowserWebFocusRestorationCurrentOwner
    ) -> Bool {
        hasPendingCandidate
            && candidateBelongsToWebView
            && gate.allowsWebPageFocus
            && windowIsKey
            && applicationIsActive
            && !windowHasAttachedSheet
            && !menuIsTracking
            && !accessibilityOwnsFocus
            && currentOwner != .other
    }
}

/// Remembers WebKit's public AppKit responder, never a DOM node.
///
/// WebKit keeps the focused element, caret, and selection in a resident view
/// while Crest moves that view between SwiftUI hosts. Restoring the same native
/// responder lets WebKit resume its own editing session without scripting the
/// page or bypassing its security-sensitive focus rules.
@MainActor
final class BrowserWebFocusRestorationController {
    private weak var webView: WKWebView?
    private weak var candidate: NSView?
    private weak var permittedOutgoingWebView: WKWebView?
    private(set) var hasPendingRestoration = false
    private var presentationFocusProtectionGeneration = 0
    private(set) var allowsNativeFocusAcquisition = true

    init(webView: WKWebView) {
        self.webView = webView
    }

    func remember(_ responder: NSView) {
        guard let webView,
            Self.isView(responder, containedIn: webView)
        else { return }
        candidate = responder
    }

    func captureBeforeDeparture() {
        guard let webView, let window = webView.window else {
            invalidate()
            return
        }
        guard let responder = window.firstResponder as? NSView,
            Self.isView(responder, containedIn: webView)
        else {
            if window.firstResponder == nil || window.firstResponder === window,
                validCandidate() != nil
            {
                return
            }
            invalidate()
            return
        }

        remember(responder)
        hasPendingRestoration = false
    }

    func requestRestoration(displacing outgoingWebView: WKWebView? = nil) {
        guard validCandidate() != nil else {
            hasPendingRestoration = false
            permittedOutgoingWebView = nil
            return
        }
        permittedOutgoingWebView = outgoingWebView
        hasPendingRestoration = true
    }

    func invalidate() {
        candidate = nil
        permittedOutgoingWebView = nil
        hasPendingRestoration = false
    }

    func beginPresentationFocusProtection() -> Int {
        // SwiftUI can replay an NSViewRepresentable's prior focus during the
        // layout that mounts an active tab. Suppress only that presentation
        // turn when chrome already owns focus; the next user event is free to
        // focus WebKit normally.
        presentationFocusProtectionGeneration &+= 1
        allowsNativeFocusAcquisition = false
        return presentationFocusProtectionGeneration
    }

    func endPresentationFocusProtection(generation: Int) {
        guard generation == presentationFocusProtectionGeneration else { return }
        allowsNativeFocusAcquisition = true
    }

    @discardableResult
    func restoreIfNeeded(
        in host: NSView,
        gate: BrowserWebFocusRestorationGate,
        applicationIsActive: Bool = NSApp.isActive,
        accessibilityOwnsFocus: Bool =
            NSWorkspace.shared.isVoiceOverEnabled
            || NSApp.isFullKeyboardAccessEnabled,
        menuIsTracking: Bool = BrowserMenuTrackingMonitor.shared.isTracking,
        windowIsKey: Bool? = nil
    ) -> Bool {
        guard hasPendingRestoration, webView != nil else { return false }
        guard let window = host.window else { return false }
        guard let candidate = validCandidate() else {
            invalidate()
            return false
        }
        guard let candidateWindow = candidate.window else {
            // The same live WebKit view may not have completed its new host
            // attachment yet. `viewDidMoveToWindow` supplies the next chance.
            return false
        }
        guard candidateWindow === window else {
            invalidate()
            return false
        }

        let currentOwner = currentOwner(
            window.firstResponder,
            candidate: candidate,
            host: host
        )
        let allowsRestoration =
            BrowserWebFocusRestorationPolicy
            .allowsRestoration(
                hasPendingCandidate: true,
                candidateBelongsToWebView: true,
                gate: gate,
                windowIsKey: windowIsKey ?? window.isKeyWindow,
                applicationIsActive: applicationIsActive,
                windowHasAttachedSheet: window.attachedSheet != nil,
                menuIsTracking: menuIsTracking,
                accessibilityOwnsFocus: accessibilityOwnsFocus,
                currentOwner: currentOwner
            )

        guard allowsRestoration else {
            // Every condition here represents an authoritative focus owner,
            // an inactive presentation, or a stale candidate. Do not turn it
            // into a delayed focus steal.
            invalidate()
            return false
        }

        hasPendingRestoration = false
        permittedOutgoingWebView = nil
        guard window.makeFirstResponder(candidate) else {
            invalidate()
            return false
        }
        return true
    }

    private func validCandidate() -> NSView? {
        guard let webView, let candidate,
            Self.isView(candidate, containedIn: webView)
        else { return nil }
        return candidate
    }

    private func currentOwner(
        _ responder: NSResponder?,
        candidate: NSView?,
        host: NSView
    ) -> BrowserWebFocusRestorationCurrentOwner {
        if responder == nil || responder === host.window || responder === host {
            return .neutral
        }
        if let candidate, responder === candidate {
            return .webContent
        }
        if let webView, let view = responder as? NSView,
            Self.isView(view, containedIn: webView)
        {
            return .webContent
        }
        if let permittedOutgoingWebView, let view = responder as? NSView,
            Self.isView(view, containedIn: permittedOutgoingWebView)
        {
            return .departingWebContent
        }
        return .other
    }

    private static func isView(_ view: NSView, containedIn ancestor: NSView) -> Bool {
        view === ancestor || view.isDescendant(of: ancestor)
    }
}

@MainActor
final class BrowserWebHostView: NSView {
    private static let lifecycleSignposter = OSSignposter(
        subsystem: "com.pauldavis.crest",
        category: "WebKitLifecycle"
    )

    private weak var hostedWebView: WKWebView?
    private(set) weak var focusRestoration: BrowserWebFocusRestorationController?
    private var focusRestorationGate = BrowserWebFocusRestorationGate.suppressed
    private var isPageActive = false
    private var focusRestorationAttemptGeneration = 0

    override func layout() {
        super.layout()
        guard let hostedWebView,
            hostedWebView.superview === self,
            hostedWebView.frame != bounds
        else { return }
        hostedWebView.frame = bounds
    }

    func attach(
        _ webView: WKWebView,
        focusRestoration: BrowserWebFocusRestorationController? = nil
    ) {
        if hostedWebView === webView {
            if webView.superview === self {
                self.focusRestoration = focusRestoration
                return
            }
            if webView.superview != nil {
                // A newer SwiftUI host has already taken ownership. A stale
                // update from a disappearing Peek must not steal it back.
                hostedWebView = nil
                self.focusRestoration = nil
                isPageActive = false
                return
            }
        }

        let attachInterval = Self.lifecycleSignposter.beginInterval(
            "Attach WKWebView"
        )
        defer {
            Self.lifecycleSignposter.endInterval(
                "Attach WKWebView",
                attachInterval
            )
        }

        let detachInterval = Self.lifecycleSignposter.beginInterval(
            "Detach Previous WKWebView"
        )
        detach()
        Self.lifecycleSignposter.endInterval(
            "Detach Previous WKWebView",
            detachInterval
        )
        self.focusRestoration = focusRestoration

        let removeInterval = Self.lifecycleSignposter.beginInterval(
            "Remove WKWebView From Parent"
        )
        webView.removeFromSuperview()
        Self.lifecycleSignposter.endInterval(
            "Remove WKWebView From Parent",
            removeInterval
        )

        // WebKit temporarily reparents rendering surfaces for features such as
        // the docked Web Inspector. Frame-based layout lets those surfaces keep
        // their geometry instead of inheriting constraints from the SwiftUI
        // host and ending up mounted but visually blank.
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds

        let addInterval = Self.lifecycleSignposter.beginInterval(
            "Add WKWebView Subview"
        )
        addSubview(webView)
        Self.lifecycleSignposter.endInterval(
            "Add WKWebView Subview",
            addInterval
        )
        hostedWebView = webView
    }

    func updateFocusPresentation(
        isPageActive: Bool,
        gate: BrowserWebFocusRestorationGate
    ) {
        self.isPageActive = isPageActive
        focusRestorationGate = gate
        focusRestorationAttemptGeneration &+= 1

        if isPageActive {
            scheduleFocusRestoration()
        }
        if !isPageActive || !gate.allowsWebPageFocus,
            let focusRestoration
        {
            let protectionGeneration =
                focusRestoration.beginPresentationFocusProtection()
            DispatchQueue.main.async { [weak focusRestoration] in
                focusRestoration?.endPresentationFocusProtection(
                    generation: protectionGeneration
                )
            }
        }
    }

    func detach() {
        guard let hostedWebView else { return }
        if hostedWebView.superview === self {
            hostedWebView.removeFromSuperview()
        }
        self.hostedWebView = nil
        focusRestoration = nil
        isPageActive = false
        focusRestorationAttemptGeneration &+= 1
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard isPageActive else { return }
        scheduleFocusRestoration()
    }

    private func scheduleFocusRestoration() {
        focusRestorationAttemptGeneration &+= 1
        let generation = focusRestorationAttemptGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                self.focusRestorationAttemptGeneration == generation,
                self.isPageActive,
                self.hostedWebView?.superview === self
            else { return }
            self.focusRestoration?.restoreIfNeeded(
                in: self,
                gate: self.focusRestorationGate
            )
        }
    }
}
