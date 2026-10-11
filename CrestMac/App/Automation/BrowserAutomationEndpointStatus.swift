import Observation

/// Whether tools can reach this launch of Crest now, which Settings shows: the
/// socket while one listens, and why there is none while automation is on and
/// the socket could not open. `BrowserMacAutomation` keeps it current.
@MainActor
@Observable
final class BrowserAutomationEndpointStatus {
    // MARK: - Types

    enum State: Equatable {
        /// No socket listens, as while automation is off.
        case closed
        /// Tools connect at `path`.
        case listening(path: String)
        /// Automation is on but the socket could not open.
        case failed(BrowserAutomationListener.Failure)
    }

    // MARK: - Variables

    var state = State.closed
}
