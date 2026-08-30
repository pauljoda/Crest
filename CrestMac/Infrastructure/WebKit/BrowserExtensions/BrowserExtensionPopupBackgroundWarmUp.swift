import WebKit

/// Retains the popup-oriented name while startup and installation paths share
/// the same WebKit background-readiness primitive.
typealias BrowserExtensionPopupBackgroundWarmUp =
    BrowserExtensionBackgroundWarmUp
typealias BrowserExtensionPopupBackgroundWarmUpObserver =
    @MainActor (BrowserExtensionPopupBackgroundWarmUp.Outcome) -> Void

/// Warms an extension background before asking WebKit to perform the action.
///
/// WebKit owns popup document loading. `performAction(for:)` is the operation
/// that makes WebKit load the popup and call the controller delegate only when
/// its web view is ready to display. Showing `action.popupPopover` directly
/// instead can expose WebKit's empty preload surface before the document has
/// loaded. A failed or missing warm-up callback must not make the button inert;
/// WebKit still gets the action and can report or recover from the failure.
@MainActor
final class BrowserExtensionPopupActionRequest {
    typealias PrepareBackground =
        @MainActor (@escaping BrowserExtensionPopupBackgroundWarmUpObserver) ->
            Void

    private let prepareBackground: PrepareBackground
    private let performAction: @MainActor () -> Void
    private let presentationDeadline: Duration?
    private let isPresentationSettled: (@MainActor () -> Bool)?
    private let presentFallback: (@MainActor () -> Void)?

    init(
        prepareBackground: @escaping PrepareBackground,
        performAction: @escaping @MainActor () -> Void,
        presentationDeadline: Duration? = nil,
        isPresentationSettled: (@MainActor () -> Bool)? = nil,
        presentFallback: (@MainActor () -> Void)? = nil
    ) {
        self.prepareBackground = prepareBackground
        self.performAction = performAction
        self.presentationDeadline = presentationDeadline
        self.isPresentationSettled = isPresentationSettled
        self.presentFallback = presentFallback
    }

    func start(
        _ observe:
            @escaping @MainActor (
                BrowserExtensionPopupBackgroundWarmUp.Outcome
            ) -> Void
    ) {
        prepareBackground { [performAction] outcome in
            observe(outcome)
            performAction()
            guard
                let presentationDeadline = self.presentationDeadline,
                let isPresentationSettled = self.isPresentationSettled,
                let presentFallback = self.presentFallback
            else {
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: presentationDeadline)
                guard !isPresentationSettled() else { return }
                presentFallback()
            }
        }
    }
}

/// Prevents WebKit from reaping an MV3 background while one of the
/// extension's own interactive surfaces is still open.
///
/// Chrome wakes a stopped service worker when an extension page sends a
/// runtime message or opens a port. WebKit can instead leave the background
/// page resident after stopping its worker; in that state the runtime call is
/// answered with nothing and `loadBackgroundContent` also reports success
/// without restarting it. Refreshing the background before WebKit's measured
/// 30-second idle boundary avoids that unrecoverable window while a popup,
/// options page, or pop-out is actively relying on its worker.
@MainActor
final class BrowserExtensionBackgroundActivityLease {
    typealias Load = BrowserExtensionPopupBackgroundWarmUp.Load

    /// WebKit has repeatedly unloaded idle MV3 backgrounds at 30 seconds.
    /// Fifteen seconds leaves a full scheduling interval of margin without
    /// keeping backgrounds active when no extension surface is open.
    nonisolated static let defaultInterval = Duration.seconds(15)

    private let interval: Duration
    private let isActive: @MainActor () -> Bool
    private let load: Load
    private var task: Task<Void, Never>?

    init(
        interval: Duration = BrowserExtensionBackgroundActivityLease
            .defaultInterval,
        isActive: @escaping @MainActor () -> Bool,
        load: @escaping Load
    ) {
        self.interval = interval
        self.isActive = isActive
        self.load = load
    }

    convenience init(
        context: WKWebExtensionContext,
        interval: Duration = BrowserExtensionBackgroundActivityLease
            .defaultInterval,
        isActive: @escaping @MainActor () -> Bool
    ) {
        self.init(
            interval: interval,
            isActive: {
                context.webExtension.hasBackgroundContent
                    && !context.webExtension.hasPersistentBackgroundContent
                    && isActive()
            },
            load: { completion in
                context.loadBackgroundContent { error in
                    MainActor.assumeIsolated { completion(error) }
                }
            }
        )
    }

    func start() {
        guard task == nil else { return }
        task = Task { @MainActor [self] in
            while !Task.isCancelled, isActive() {
                load { _ in }
                try? await Task.sleep(for: interval)
            }
            task = nil
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
