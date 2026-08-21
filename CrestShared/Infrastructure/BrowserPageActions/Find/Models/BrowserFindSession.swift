import Observation
import WebKit

@Observable
@MainActor
final class BrowserFindSession {
    private(set) var isPresented = false
    private(set) var matchState = BrowserFindMatchState.idle

    /// Bumped every time the page is asked for find, presented or not.
    ///
    /// Asking for find is always a request for the query field, and the bar is
    /// often already on screen when it is asked for a second time — the reader
    /// searched, clicked into the page, and reached for the shortcut again.
    /// `isPresented` cannot carry that: it is already true, so nothing the bar
    /// observes changes and the field stays wherever focus went. This counter
    /// changes on every ask, which is what the bar takes focus from.
    private(set) var focusRequest = 0

    @ObservationIgnored private var generation = 0

    func present(hasLoadedPage: Bool) {
        guard hasLoadedPage else { return }
        isPresented = true
        focusRequest &+= 1
    }

    func dismiss(using executor: any BrowserFindExecuting) {
        generation &+= 1
        matchState = .idle
        isPresented = false
        clear(using: executor)
    }

    func find(
        _ query: String,
        direction: BrowserFindDirection = .forward,
        using executor: any BrowserFindExecuting
    ) {
        generation &+= 1
        let requestGeneration = generation
        guard !query.isEmpty else {
            matchState = .idle
            clear(using: executor)
            return
        }

        matchState = .searching
        executor.performFind(
            query,
            configuration: Self.configuration(for: direction)
        ) { [weak self] matchFound in
            guard let self, generation == requestGeneration else { return }
            matchState = matchFound ? .found : .notFound
        }
    }

    private func clear(using executor: any BrowserFindExecuting) {
        executor.performFind("", configuration: WKFindConfiguration()) { _ in }
    }

    private static func configuration(
        for direction: BrowserFindDirection
    ) -> WKFindConfiguration {
        let configuration = WKFindConfiguration()
        configuration.backwards = direction == .backward
        configuration.caseSensitive = false
        configuration.wraps = true
        return configuration
    }
}
