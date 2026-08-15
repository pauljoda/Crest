import Observation
import WebKit

@Observable
@MainActor
final class BrowserFindSession {
    private(set) var isPresented = false
    private(set) var matchState = BrowserFindMatchState.idle

    @ObservationIgnored private var generation = 0

    func present(hasLoadedPage: Bool) {
        guard hasLoadedPage else { return }
        isPresented = true
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
