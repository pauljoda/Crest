import WebKit

/// Resolves one extension-popup background preparation attempt.
///
/// Reading `WKWebExtension.Action.popupPopover` preloads the popup document
/// straight away, and WebKit evicts a nonpersistent background seconds into a
/// session. A popup that loads while its background is not running has its
/// opening `runtime` message answered with nothing at all, and an extension
/// that reads that reply without guarding it never leaves its startup loader:
/// Dark Reader destructures the answer, so the exception it throws leaves the
/// promise its popup awaits unsettled forever.
///
/// A deadline still bounds versions of WebKit that fail to call the completion
/// handler, but a deadline is not a successful load. Keeping those outcomes
/// distinct prevents the caller from presenting a popup whose startup request
/// has no live background recipient.
@MainActor
final class BrowserExtensionPopupBackgroundWarmUp {
    enum Outcome {
        case loaded
        case failed(any Error)
        case timedOut
    }

    typealias Load =
        @MainActor (@escaping @MainActor ((any Error)?) -> Void) -> Void

    /// Long enough for a cold background to come up — a small one measured
    /// about 340ms, and a background document only reports loaded after its
    /// modules finish evaluating, which for a password manager's
    /// multi-megabyte worker takes over a second — and short enough that an
    /// extension whose background never loads still opens its popup while
    /// the click that asked for it is remembered.
    nonisolated static let defaultDeadline = Duration.milliseconds(3000)

    private let deadline: Duration
    private let load: Load
    private var hasFinished = false

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
                loaded(nil)
                return
            }
            guard context.webExtension.hasBackgroundContent else {
                loaded(nil)
                return
            }
            context.loadBackgroundContent { error in
                MainActor.assumeIsolated { loaded(error) }
            }
        }
    }

    /// Reports the first terminal result, exactly once.
    func prepare(
        _ body: @escaping @MainActor (Outcome) -> Void
    ) {
        load { [self] error in
            finish(
                error.map(Outcome.failed) ?? .loaded,
                body
            )
        }
        Task { @MainActor [self] in
            try? await Task.sleep(for: deadline)
            finish(.timedOut, body)
        }
    }

    private func finish(
        _ outcome: Outcome,
        _ body: @MainActor (Outcome) -> Void
    ) {
        guard !hasFinished else { return }
        hasFinished = true
        body(outcome)
    }
}
