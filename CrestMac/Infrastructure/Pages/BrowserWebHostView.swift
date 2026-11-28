import AppKit
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

    /// Whether a remembered responder may take focus back through this gate,
    /// with everything else that could own focus at that moment.
    func allowsRestoration(
        hasPendingCandidate: Bool,
        candidateBelongsToWebView: Bool,
        windowIsKey: Bool,
        applicationIsActive: Bool,
        windowHasAttachedSheet: Bool,
        menuIsTracking: Bool,
        accessibilityOwnsFocus: Bool,
        currentOwner: BrowserWebFocusRestorationCurrentOwner
    ) -> Bool {
        hasPendingCandidate
            && candidateBelongsToWebView
            && allowsWebPageFocus
            && windowIsKey
            && applicationIsActive
            && !windowHasAttachedSheet
            && !menuIsTracking
            && !accessibilityOwnsFocus
            && currentOwner != .other
    }

    /// Whether the page may take a keyboard nothing in its window holds, as
    /// a page in a browser takes it once the address field or the palette
    /// lets go, or as it comes on screen. Nothing is taken from anyone, so
    /// unlike a restoration it does not give way to assistive technologies;
    /// Crest's own chrome, another window, a sheet or a menu still keeps it.
    func allowsTakingUnheldKeyboard(
        windowIsKey: Bool,
        applicationIsActive: Bool,
        windowHasAttachedSheet: Bool,
        menuIsTracking: Bool
    ) -> Bool {
        allowsWebPageFocus
            && windowIsKey
            && applicationIsActive
            && !windowHasAttachedSheet
            && !menuIsTracking
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

/// Remembers the engine's public AppKit responder, never a DOM node.
///
/// An engine keeps the focused element, caret, and selection in a resident view
/// while Crest moves that view between SwiftUI hosts. Restoring the same native
/// responder lets it resume its own editing session without scripting the
/// page or bypassing its security-sensitive focus rules.
@MainActor
final class BrowserWebFocusRestorationController {
    private weak var webView: NSView?
    private weak var candidate: NSView?
    private weak var permittedOutgoingWebView: NSView?
    private(set) var hasPendingRestoration = false
    private var presentationFocusProtectionGeneration = 0
    private(set) var allowsNativeFocusAcquisition = true

    init(webView: NSView) {
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

    /// Takes the responder already inside the web view as the page's own,
    /// when focus reached the page ahead of the selection that makes it the
    /// focused one, as a click in an unfocused split card does. Nothing is
    /// left to restore, so an older candidate cannot take focus from it.
    func adoptCurrentFocus() -> Bool {
        guard let webView, let responder = webView.window?.firstResponder as? NSView,
            Self.isView(responder, containedIn: webView)
        else { return false }
        candidate = responder
        permittedOutgoingWebView = nil
        hasPendingRestoration = false
        return true
    }

    /// Asks for the page itself to take focus once its chrome lets go, as
    /// closing find does: the responder it last held, or its own view when it
    /// never held one, since an engine that keeps no record of its responder,
    /// as Chromium does not, focuses its page from there. A page that already
    /// holds focus keeps the responder it has. Focus may be taken from
    /// `outgoingWebView`, a page giving way to this one, as a closing Peek is.
    func requestPageFocus(displacing outgoingWebView: NSView? = nil) {
        guard let webView, !adoptCurrentFocus() else { return }
        if validCandidate() == nil { candidate = webView }
        permittedOutgoingWebView = outgoingWebView
        hasPendingRestoration = true
    }

    func requestRestoration(displacing outgoingWebView: NSView? = nil) {
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
        // focus the page normally.
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
            // The same live engine view may not have completed its new host
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
            gate.allowsRestoration(
                hasPendingCandidate: true,
                candidateBelongsToWebView: true,
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

    /// Gives the page the keyboard when nothing in its window holds it: the
    /// responder it last held, or its own view, from which its engine focuses
    /// what the page itself focused, such as a field it focused as it loaded.
    /// A pending restoration goes first.
    @discardableResult
    func takeUnheldKeyboard(
        in host: NSView,
        gate: BrowserWebFocusRestorationGate,
        applicationIsActive: Bool = NSApp.isActive,
        menuIsTracking: Bool = BrowserMenuTrackingMonitor.shared.isTracking,
        windowIsKey: Bool? = nil
    ) -> Bool {
        guard !hasPendingRestoration, let webView, let window = host.window, webView.window === window,
            currentOwner(window.firstResponder, candidate: nil, host: host) == .neutral,
            gate.allowsTakingUnheldKeyboard(
                windowIsKey: windowIsKey ?? window.isKeyWindow,
                applicationIsActive: applicationIsActive,
                windowHasAttachedSheet: window.attachedSheet != nil,
                menuIsTracking: menuIsTracking
            )
        else { return false }
        return window.makeFirstResponder(validCandidate() ?? webView)
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

/// How a window shows the page in one of its hosts.
enum BrowserPagePresentation {
    /// Off screen, in a Space the window does not show. The Space keeps its
    /// page's view in its host so the page keeps its place, but the page's
    /// engine treats it as hidden, as it does a tab the person switched away
    /// from.
    case hidden
    /// On screen in a Space the person swipes to or from, which draws the
    /// page as it moves. The engine keeps rendering the page, which takes no
    /// input or focus until its Space settles.
    case preview
    /// The page the window presents to the person.
    case presented
}

/// Optional engine hooks. The host owns AppKit attachment and focus; an
/// adapter owns engine-specific observers such as WebKit's link-hover overlay.
@MainActor
protocol BrowserNativePageSurfaceLifecycle: AnyObject {
    func didAttach(to host: BrowserWebHostView)
    /// The view leaves `host`, for another host or out of its window. A view
    /// moving to another host in the same window stays on screen throughout.
    func willDetach(from host: BrowserWebHostView)
    /// The host showing this view changed how it shows its page, as its
    /// Space did, while the view stayed in it; see
    /// `BrowserWebHostView.presentation`.
    func presentationDidChange(in host: BrowserWebHostView)
    func presentationGeometryDidChange()
    /// Whether a page this view gives way to should stay on screen above the
    /// view that replaces it until that one has drawn. An engine whose page
    /// draws nothing for a few frames after it is shown again sets it, so a
    /// tab switch never shows the page's bare background in between.
    var holdsReplacedPageUntilDrawn: Bool { get }
}

extension BrowserNativePageSurfaceLifecycle {
    func presentationDidChange(in host: BrowserWebHostView) {}
    func presentationGeometryDidChange() {}
    var holdsReplacedPageUntilDrawn: Bool { false }
}

/// Shows a page's engine-owned view where SwiftUI placed this host.
///
/// SwiftUI can hold two hosts for one page at once, and either can be the one
/// it dismantles first. It keeps updating an outgoing host after the incoming
/// one claimed the view, and an outgoing subtree that still renders during its
/// removal, such as the window's chrome giving way to a page shown fullscreen,
/// can build a host for the page after the incoming one did. The newest claim
/// shows the view, a stale update never takes it back, and when the host
/// showing it lets go, the view returns to the newest host still claiming it
/// in the same window, so it always ends up in whichever host survives. A
/// host in another window keeps waiting for its own window to present the
/// page again. A host the window does not draw gives the view to the newest
/// one it does: the Spaces of a group each hold a host for a pinned tab they
/// share, and its page shows in the one on screen, whichever claimed it last.
///
/// A page view moving between hosts of one window never leaves the window,
/// which would hide its page from its engine and take its focus: a page shown
/// again draws nothing for a few frames, and an engine that kept the page
/// focused while AppKit took focus away can leave it unable to follow the
/// pointer. SwiftUI makes a host before it places it in a window, and can
/// dismantle the host it replaces before it makes the new one, as when a page
/// enters or leaves full screen. A host claiming a view while it has no window
/// shows it once it joins one, and a dismantled host leaves the view in the
/// window, out of sight, for the host that takes its place.
@MainActor
final class BrowserWebHostView: NSView {
    // MARK: - Static Variables

    private static let lifecycleSignposter = DiagnosticLog.surfaceLifecycle.signposter
    /// Every host that claimed a page view and has not let it go.
    private static let claimants = NSHashTable<BrowserWebHostView>.weakObjects()
    /// The number of claims made so far, which orders them.
    private static var claimCount = 0
    /// How many display frames a replaced page stays above the page that
    /// replaced it: about 42 ms at 120 Hz, longer than the frames a page
    /// shown again takes to draw.
    private static let replacementHoldFrames = 5
    /// Page views a dismantled host let go of, kept in their window out of
    /// sight until a host there shows them, each with the number of its keep;
    /// see `keep(_:in:)`.
    private static let keptWebViews = NSMapTable<NSView, NSNumber>.weakToStrongObjects()
    /// The number of keeps so far, which tells a keep's wait from a later one.
    private static var keepCount = 0
    /// How long a kept page view waits for a host before it leaves its
    /// window: longer than SwiftUI takes to make and place the host replacing
    /// a dismantled one, which can take several turns of the main queue.
    private static let keptWebViewWait = Duration.milliseconds(500)

    // MARK: - Variables

    private weak var hostedWebView: NSView?
    private(set) weak var focusRestoration: BrowserWebFocusRestorationController?
    /// The window this host was last in, which it keeps while SwiftUI takes it
    /// out of the window on its way to being dismantled.
    private weak var lastWindow: NSWindow?
    /// Keeps the window server from dragging the window by this page's top.
    private lazy var titleBarTracker = BrowserTitleBarPointerTracker(view: self, region: .page)
    private var titleBarTrackingArea: NSTrackingArea?
    private var focusRestorationGate = BrowserWebFocusRestorationGate.suppressed
    private var isPageActive = false
    /// How the window shows this host's page. A Space keeps its page's view
    /// in its host whether the window shows the Space or not, so the page
    /// keeps its place and its Space's preview draws it as the person swipes.
    private(set) var presentation = BrowserPagePresentation.presented
    private var focusRestorationAttemptGeneration = 0
    /// Whether the page waits to take a keyboard nothing in the window holds:
    /// it came on screen here or became the window's page, Crest's chrome let
    /// go of the keyboard, or whatever held it in the window let go. It waits
    /// until it has the keyboard, so a window that was not key, or had a
    /// sheet, hands it over once it becomes key or the sheet ends.
    private var takesUnheldKeyboard = false
    /// Watches the window's keyboard, which the page takes when it is let go.
    private var firstResponderObservation: NSKeyValueObservation?
    /// When this host claimed `hostedWebView`: the newest claim is the largest.
    private var claim = 0
    /// Whether this host claimed `hostedWebView` while the view was in a
    /// window and this host was not, and shows it once it joins one.
    private var awaitsWindow = false
    /// The page view this host showed before `hostedWebView`, still shown
    /// above it while the new one draws its first frames; see
    /// `holdsReplacedPageUntilDrawn`.
    private var replacedWebView: NSView?
    private var replacedFramesLeft = 0
    private var replacedDisplayLink: CADisplayLink?

    // MARK: - Actions - Hosting

    /// Claims `webView` and shows it here, unless `allowsAttachment` says this
    /// host's window no longer presents the page, which lets it go. Asking
    /// again for the view this host already claimed changes nothing, even when
    /// a newer host took it meanwhile: that host shows it until it lets go.
    func attach(
        _ webView: NSView,
        focusRestoration: BrowserWebFocusRestorationController? = nil,
        allowsAttachment: Bool = true
    ) {
        guard allowsAttachment else {
            detach()
            return
        }
        if hostedWebView === webView {
            if awaitsWindow {
                self.focusRestoration = focusRestoration
                return
            }
            if webView.superview === self {
                self.focusRestoration = focusRestoration
                return
            }
            if webView.superview != nil {
                // A newer SwiftUI host has already taken ownership. A stale
                // update from a disappearing Peek must not steal it back.
                // Keep the claim so repeated updates remain stale; an
                // unattached view can still return through the path below.
                self.focusRestoration = nil
                isPageActive = false
                Self.showWhereDrawn(webView)
                return
            }
        }

        let attachInterval = Self.lifecycleSignposter.beginInterval(
            "Attach Page View"
        )
        defer {
            Self.lifecycleSignposter.endInterval(
                "Attach Page View",
                attachInterval
            )
        }

        let detachInterval = Self.lifecycleSignposter.beginInterval(
            "Detach Previous Page View"
        )
        let replaced = replaceableWebView()
        if let replaced {
            letGo(keepingOnScreen: replaced)
        } else {
            detach()
        }
        Self.lifecycleSignposter.endInterval(
            "Detach Previous Page View",
            detachInterval
        )
        Self.claimCount &+= 1
        claim = Self.claimCount
        hostedWebView = webView
        Self.claimants.add(self)
        // Taken into a host outside any window, a view on screen would leave
        // its window; it waits where it is until this host joins one.
        guard window != nil || webView.window == nil else {
            awaitsWindow = true
            self.focusRestoration = focusRestoration
            return
        }
        show(webView, focusRestoration: focusRestoration, below: replaced)
        if let replaced { holdUntilReplacementDraws(replaced) }
    }

    /// Lets go of the view this host claimed. When it was showing it, the view
    /// moves to the newest other host in its window that still claims it, or
    /// else leaves the window.
    func detach() {
        detach(keepingInWindow: false)
    }

    /// SwiftUI took this host down. A view it showed stays in the window, out
    /// of sight, for the host SwiftUI puts in its place, which it makes and
    /// places only after it dismantles this one. A page its host kept off
    /// screen leaves the window as it did: kept out of sight, it would count
    /// as presented, and its engine would show it and give it focus.
    func dismantle() {
        detach(keepingInWindow: true)
    }

    private func detach(keepingInWindow: Bool) {
        releaseReplacedWebView()
        awaitsWindow = false
        guard let hostedWebView else { return }
        Self.claimants.remove(self)
        let showsHostedWebView = hostedWebView.superview === self
        let focusRestoration = focusRestoration
        let placement = window ?? lastWindow
        self.hostedWebView = nil
        self.focusRestoration = nil
        isPageActive = false
        takesUnheldKeyboard = false
        focusRestorationAttemptGeneration &+= 1
        guard showsHostedWebView else { return }
        (hostedWebView as? any BrowserNativePageSurfaceLifecycle)?.willDetach(from: self)
        let successor = Self.successor(for: hostedWebView, in: placement)
        if let successor, successor.window != nil || hostedWebView.window == nil {
            successor.show(hostedWebView, focusRestoration: focusRestoration)
        } else if let window = hostedWebView.window, presentation != .hidden, successor != nil || keepingInWindow {
            Self.keep(hostedWebView, in: window)
        } else {
            hostedWebView.removeFromSuperview()
        }
    }

    /// Whether this host is in `window`, or either has yet to join one.
    private func isPlaced(with window: NSWindow?) -> Bool {
        guard let window, let placement = self.window ?? lastWindow else { return true }
        return placement === window
    }

    /// Whether the window draws this host: it is in one, and neither it nor a
    /// view it is in is hidden.
    private var isDrawn: Bool { window != nil && !isHiddenOrHasHiddenAncestor }

    /// The host in `window` that shows `webView` when the one showing it lets
    /// go or goes off screen: the newest claim the window draws, or else the
    /// newest claim.
    private static func successor(for webView: NSView, in window: NSWindow?) -> BrowserWebHostView? {
        claimants.allObjects
            .filter { $0.hostedWebView === webView && $0.isPlaced(with: window) }
            .max { ($0.isDrawn ? 1 : 0, $0.claim) < ($1.isDrawn ? 1 : 0, $1.claim) }
    }

    /// Keeps `webView`, which a host in `window` let go of, in the window out
    /// of sight, for a host there that has yet to show it: one waiting to join
    /// the window, or one SwiftUI has yet to make. A view no host showed
    /// within `keptWebViewWait` goes to the window's newest host still
    /// claiming it, or else leaves the window.
    private static func keep(_ webView: NSView, in window: NSWindow) {
        guard let content = window.contentView, let frame = content.superview else {
            webView.removeFromSuperview()
            return
        }
        keepCount &+= 1
        let keep = keepCount
        keptWebViews.setObject(NSNumber(value: keep), forKey: webView)
        webView.alphaValue = 0
        frame.addSubview(webView, positioned: .below, relativeTo: content)
        Task { @MainActor [weak webView] in
            try? await Task.sleep(for: keptWebViewWait)
            guard let webView, keptWebViews.object(forKey: webView)?.intValue == keep else { return }
            if let host = successor(for: webView, in: webView.window), host.window != nil {
                host.show(webView, focusRestoration: nil)
                if host.isPageActive { host.scheduleFocusRestoration() }
            } else {
                keptWebViews.removeObject(forKey: webView)
                webView.removeFromSuperview()
                webView.alphaValue = 1
            }
        }
    }

    /// Moves `webView` from the host showing it, which the window no longer
    /// draws, to the newest host claiming it that the window does draw.
    private static func showWhereDrawn(_ webView: NSView) {
        guard let showing = webView.superview as? BrowserWebHostView, !showing.isDrawn,
            let host = successor(for: webView, in: showing.window ?? showing.lastWindow), host.isDrawn
        else { return }
        let focusRestoration = showing.focusRestoration
        (webView as? any BrowserNativePageSurfaceLifecycle)?.willDetach(from: showing)
        host.show(webView, focusRestoration: focusRestoration)
        if host.isPageActive { host.scheduleFocusRestoration() }
    }

    // MARK: - Actions - Replacement

    /// The view this host shows now, when the view replacing it should wait
    /// beneath it until it draws: it is on screen here, asks for that, and
    /// no other host claims it, which would take it once this host lets go.
    /// A replacement still in progress ends first.
    private func replaceableWebView() -> NSView? {
        releaseReplacedWebView()
        guard let hostedWebView, hostedWebView.superview === self, window != nil,
            (hostedWebView as? any BrowserNativePageSurfaceLifecycle)?.holdsReplacedPageUntilDrawn == true,
            !Self.claimants.allObjects.contains(where: { $0 !== self && $0.hostedWebView === hostedWebView })
        else { return nil }
        return hostedWebView
    }

    /// Lets go of `webView` as `detach` does, but leaves it on screen.
    private func letGo(keepingOnScreen webView: NSView) {
        Self.claimants.remove(self)
        awaitsWindow = false
        hostedWebView = nil
        focusRestoration = nil
        isPageActive = false
        takesUnheldKeyboard = false
        focusRestorationAttemptGeneration &+= 1
    }

    /// Keeps `webView` above its replacement for a few display frames: a
    /// page shown again draws nothing until its engine composes a frame for
    /// it, about two to four frames, and the one it replaces covers that
    /// instead of the page's bare background.
    private func holdUntilReplacementDraws(_ webView: NSView) {
        replacedWebView = webView
        replacedFramesLeft = Self.replacementHoldFrames
        let link = displayLink(target: self, selector: #selector(replacementFrameElapsed(_:)))
        link.add(to: .main, forMode: .common)
        replacedDisplayLink = link
    }

    @objc private func replacementFrameElapsed(_ link: CADisplayLink) {
        replacedFramesLeft -= 1
        if replacedFramesLeft <= 0 { releaseReplacedWebView() }
    }

    /// Takes the replaced view off screen, which hides its page.
    private func releaseReplacedWebView() {
        replacedDisplayLink?.invalidate()
        replacedDisplayLink = nil
        guard let replaced = replacedWebView else { return }
        replacedWebView = nil
        guard replaced.superview === self else { return }
        (replaced as? any BrowserNativePageSurfaceLifecycle)?.willDetach(from: self)
        replaced.removeFromSuperview()
    }

    // MARK: - Actions - Showing

    /// Puts `webView`, which this host claimed, on screen here, beneath
    /// `replaced` while that one is held there.
    private func show(
        _ webView: NSView, focusRestoration: BrowserWebFocusRestorationController?, below replaced: NSView? = nil
    ) {
        self.focusRestoration = focusRestoration ?? self.focusRestoration
        awaitsWindow = false

        // A view in this host's window, in another host or kept for one,
        // moves straight across without leaving the window.
        if window == nil || webView.window !== window {
            let removeInterval = Self.lifecycleSignposter.beginInterval(
                "Remove Page View From Parent"
            )
            webView.removeFromSuperview()
            Self.lifecycleSignposter.endInterval(
                "Remove Page View From Parent",
                removeInterval
            )
        }
        if Self.keptWebViews.object(forKey: webView) != nil {
            Self.keptWebViews.removeObject(forKey: webView)
            webView.alphaValue = 1
        }

        // WebKit temporarily reparents rendering surfaces for features such as
        // the docked Web Inspector. Frame-based layout lets those surfaces keep
        // their geometry instead of inheriting constraints from the SwiftUI
        // host and ending up mounted but visually blank.
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        if !bounds.isEmpty {
            webView.frame = bounds
        }

        let addInterval = Self.lifecycleSignposter.beginInterval(
            "Add Page View Subview"
        )
        if let replaced, replaced.superview === self {
            addSubview(webView, positioned: .below, relativeTo: replaced)
        } else {
            addSubview(webView)
        }
        Self.lifecycleSignposter.endInterval(
            "Add Page View Subview",
            addInterval
        )
        // A page coming on screen takes a keyboard nothing holds once it is
        // the window's page.
        takesUnheldKeyboard = true
        (webView as? any BrowserNativePageSurfaceLifecycle)?.didAttach(to: self)
    }

    /// Whether the page may take focus as it comes back on screen: it is its
    /// window's focused page and nothing of Crest's, such as the address
    /// field or the command palette, owns focus.
    var allowsPageFocus: Bool { isPageActive && focusRestorationGate.allowsWebPageFocus }

    // MARK: - Actions - Presentation

    /// Tells the page's engine the window changed how it shows the page: the
    /// page left the screen or came back, as a tab switch does by moving the
    /// page's view out of and into a host, or its Space's preview settled.
    /// The view stays here all along.
    func updatePresentation(_ presentation: BrowserPagePresentation) {
        guard presentation != self.presentation else { return }
        self.presentation = presentation
        guard let hostedWebView, hostedWebView.superview === self else { return }
        (hostedWebView as? any BrowserNativePageSurfaceLifecycle)?.presentationDidChange(in: self)
        if presentation == .presented, isPageActive, takesUnheldKeyboard { scheduleFocusRestoration() }
    }

    // MARK: - Actions - Focus

    func updateFocusPresentation(
        isPageActive: Bool,
        gate: BrowserWebFocusRestorationGate
    ) {
        // Becoming the window's page, or Crest's chrome letting go of the
        // keyboard, hands the page a keyboard nothing else holds.
        let opensToPage =
            isPageActive
            && (!self.isPageActive || (gate.allowsWebPageFocus && !focusRestorationGate.allowsWebPageFocus))
        self.isPageActive = isPageActive
        focusRestorationGate = gate
        focusRestorationAttemptGeneration &+= 1
        if !isPageActive { takesUnheldKeyboard = false }

        if isPageActive {
            scheduleFocusRestoration(takingUnheldKeyboard: opensToPage)
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

    /// Restores the page's focus on the next turn, once SwiftUI settled what
    /// owns the keyboard, or, when `takingUnheldKeyboard` or an earlier
    /// attempt asks, gives the page a keyboard nothing holds.
    private func scheduleFocusRestoration(takingUnheldKeyboard: Bool = false) {
        if takingUnheldKeyboard { takesUnheldKeyboard = true }
        focusRestorationAttemptGeneration &+= 1
        let generation = focusRestorationAttemptGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                self.focusRestorationAttemptGeneration == generation,
                self.isPageActive,
                self.hostedWebView?.superview === self,
                let focusRestoration = self.focusRestoration
            else { return }
            if focusRestoration.restoreIfNeeded(in: self, gate: self.focusRestorationGate) {
                self.takesUnheldKeyboard = false
                return
            }
            // A Space the person swipes through takes the keyboard once it
            // settles.
            guard self.takesUnheldKeyboard, self.presentation == .presented else { return }
            if focusRestoration.takeUnheldKeyboard(in: self, gate: self.focusRestorationGate)
                || self.pageHoldsKeyboard
            {
                self.takesUnheldKeyboard = false
            }
        }
    }

    /// Whether the window's keyboard is in this host's page.
    private var pageHoldsKeyboard: Bool {
        guard let hostedWebView, let responder = window?.firstResponder as? NSView else { return false }
        return responder === hostedWebView || responder.isDescendant(of: hostedWebView)
    }

    /// Hands the page the keyboard whenever whatever held it in the window
    /// lets go, as the palette's field does as the palette closes, and once
    /// the window becomes key or its sheet ends while the page waits for it.
    private func watchWindow() {
        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
        center.removeObserver(self, name: NSWindow.didEndSheetNotification, object: nil)
        guard let window else {
            firstResponderObservation = nil
            return
        }
        firstResponderObservation = window.observe(\.firstResponder) { [weak self] window, _ in
            MainActor.assumeIsolated {
                guard let self, self.isPageActive,
                    window.firstResponder == nil || window.firstResponder === window
                else { return }
                self.scheduleFocusRestoration(takingUnheldKeyboard: true)
            }
        }
        center.addObserver(
            self, selector: #selector(windowMayHandOverKeyboard), name: NSWindow.didBecomeKeyNotification,
            object: window)
        center.addObserver(
            self, selector: #selector(windowMayHandOverKeyboard), name: NSWindow.didEndSheetNotification,
            object: window)
    }

    @objc private func windowMayHandOverKeyboard(_ notification: Notification) {
        guard isPageActive, takesUnheldKeyboard else { return }
        scheduleFocusRestoration()
    }

    // MARK: - Actions - Keyboard

    /// Whether `responder` is a page's own view shown in a host, or a view
    /// inside it, such as the engine's content view or an inspector docked
    /// beside the page, rather than one of Crest's.
    static func isPageContent(_ responder: NSResponder?) -> Bool {
        var view = responder as? NSView
        while let current = view, let superview = current.superview {
            if let host = superview as? BrowserWebHostView { return host.hostedWebView === current }
            view = superview
        }
        return false
    }

    override func keyDown(with event: NSEvent) {
        guard let hostedWebView,
            let responder = window?.firstResponder as? NSView,
            responder === hostedWebView || responder.isDescendant(of: hostedWebView)
        else {
            super.keyDown(with: event)
            return
        }

        // The engine has already offered this key to the page and its input
        // context. Preserve native fallback handlers without interpreting or
        // dispatching the key to the engine again. Only the terminal, unhandled
        // key-down feedback is unnecessary in a browsing view.
        let fallback = BrowserWebKeyboardFallback()
        var tail: NSResponder = self
        while let next = tail.nextResponder {
            tail = next
        }
        tail.nextResponder = fallback
        defer {
            if tail.nextResponder === fallback {
                tail.nextResponder = fallback.nextResponder
            }
        }
        super.keyDown(with: event)
    }

    // MARK: - Actions - Layout

    override func layout() {
        super.layout()
        layoutHostedWebView()
        titleBarTracker.checkPointerSoon()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        // SwiftUI can give an entering or departing host an empty frame. Do
        // not send that transient viewport to the engine's rendering process.
        layoutHostedWebView()
    }

    private func layoutHostedWebView() {
        guard !bounds.isEmpty,
            let hostedWebView,
            hostedWebView.superview === self,
            hostedWebView.frame != bounds
        else { return }
        hostedWebView.frame = bounds
    }

    // MARK: - Actions - Window

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            titleBarTracker.release()
            releaseReplacedWebView()
            firstResponderObservation = nil
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didEndSheetNotification, object: nil)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window { lastWindow = window }
        if window != nil, awaitsWindow { showAwaitedWebView() }
        trackTitleBarPointer()
        watchWindow()
        guard isPageActive else { return }
        scheduleFocusRestoration(takingUnheldKeyboard: true)
    }

    /// Shows the view this host claimed before it was in a window, now that
    /// it is in one, unless a newer claim shows it in any window: that host
    /// keeps it until it lets go, as a stale update never takes it back.
    private func showAwaitedWebView() {
        awaitsWindow = false
        guard let hostedWebView, hostedWebView.superview !== self else { return }
        if let showing = hostedWebView.superview as? BrowserWebHostView, showing.claim > claim, showing.isDrawn {
            return
        }
        show(hostedWebView, focusRestoration: focusRestoration)
    }

    override func viewDidHide() {
        super.viewDidHide()
        titleBarTracker.release()
        if let hostedWebView { Self.showWhereDrawn(hostedWebView) }
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        titleBarTracker.checkPointerSoon()
        if let hostedWebView { Self.showWhereDrawn(hostedWebView) }
    }

    private func trackTitleBarPointer() {
        guard window != nil else { return }
        if titleBarTrackingArea == nil {
            let area = titleBarTracker.makeTrackingArea()
            addTrackingArea(area)
            titleBarTrackingArea = area
        }
        titleBarTracker.checkPointerSoon()
    }
}

@MainActor
private final class BrowserWebKeyboardFallback: NSResponder {
    override func noResponder(for eventSelector: Selector) {
        guard eventSelector != #selector(NSResponder.keyDown(with:)) else { return }
        super.noResponder(for: eventSelector)
    }
}
