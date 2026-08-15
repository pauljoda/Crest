import WebKit

/// Runs one extension-popup presentation, after the extension's background
/// content has been loaded or after a deadline passes, whichever comes first.
///
/// Reading `WKWebExtension.Action.popupPopover` preloads the popup document
/// straight away, and WebKit evicts a nonpersistent background seconds into a
/// session. A popup that loads while its background is not running has its
/// opening `runtime` message answered with nothing at all, and an extension
/// that reads that reply without guarding it never leaves its startup loader:
/// Dark Reader destructures the answer, so the exception it throws leaves the
/// promise its popup awaits unsettled forever.
///
/// The deadline is load-bearing rather than defensive. When background content
/// genuinely fails to load, WebKit never calls `loadBackgroundContent`'s
/// completion handler at all, so waiting on that alone would leave a broken
/// extension's toolbar button inert.
@MainActor
final class BrowserExtensionPopupBackgroundWarmUp {
    typealias Load = @MainActor (@escaping @MainActor () -> Void) -> Void

    /// Long enough for a cold background to come up — one measured about
    /// 340ms — and short enough that an extension whose background never
    /// loads still opens its popup while the click that asked for it is
    /// remembered.
    nonisolated static let defaultDeadline = Duration.milliseconds(1500)

    private let deadline: Duration
    private let load: Load
    private var hasPresented = false

    init(
        deadline: Duration = BrowserExtensionPopupBackgroundWarmUp
            .defaultDeadline,
        load: @escaping Load
    ) {
        self.deadline = deadline
        self.load = load
    }

    convenience init(
        context: WKWebExtensionContext?,
        deadline: Duration = BrowserExtensionPopupBackgroundWarmUp
            .defaultDeadline
    ) {
        self.init(deadline: deadline) { loaded in
            guard let context else {
                loaded()
                return
            }
            context.loadBackgroundContent { _ in
                MainActor.assumeIsolated { loaded() }
            }
        }
    }

    /// Runs `body` once the background content is loaded or once the deadline
    /// passes, whichever arrives first, and only ever once.
    func present(_ body: @escaping @MainActor () -> Void) {
        load { [self] in presentOnce(body) }
        Task { @MainActor [self] in
            try? await Task.sleep(for: deadline)
            presentOnce(body)
        }
    }

    private func presentOnce(_ body: @MainActor () -> Void) {
        guard !hasPresented else { return }
        hasPresented = true
        body()
    }
}
