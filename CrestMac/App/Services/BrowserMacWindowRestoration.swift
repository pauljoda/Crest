import AppKit

/// Which window each browser scene presents while AppKit restores a launch's
/// windows.
///
/// SwiftUI builds a restored window's content before it hands back the request
/// the window was saved with. Until AppKit has restored every window, a scene
/// without a request may still be a restored window waiting for its own, so it
/// must not take the initial window's place.
@MainActor
final class BrowserMacWindowRestoration {
    // MARK: - Variables

    private let center: NotificationCenter
    private var observers: [any NSObjectProtocol] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var isFinished = false

    // MARK: - Initializers

    /// Watches `center` for the end of this launch's window restoration, so it
    /// must exist before the application finishes launching. AppKit reports
    /// the end on every launch, including one with nothing to restore, and
    /// finishing launch follows it.
    init(center: NotificationCenter = .default) {
        self.center = center
        let ends = [NSApplication.didFinishRestoringWindowsNotification, NSApplication.didFinishLaunchingNotification]
        for name in ends {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.finish() }
                })
        }
    }

    isolated deinit {
        observers.forEach(center.removeObserver)
    }

    // MARK: - Actions - Windows

    /// The window a scene presents once every window is restored: the request
    /// SwiftUI restored into `scene` by then, or for a scene still without
    /// one, the window `coordinator` opens by default. A scene that went away
    /// while it waited presents none.
    func window(
        presentedBy scene: () -> BrowserMacWindowRequest?, in coordinator: BrowserMacWindowCoordinator
    ) async -> BrowserMacWindowRequest? {
        if !isFinished { await withCheckedContinuation { waiting.append($0) } }
        if let restored = scene() { return restored }
        return Task.isCancelled ? nil : coordinator.defaultWindowRequest()
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        observers.forEach(center.removeObserver)
        observers.removeAll()
        let resumed = waiting
        waiting.removeAll()
        for continuation in resumed { continuation.resume() }
    }
}
