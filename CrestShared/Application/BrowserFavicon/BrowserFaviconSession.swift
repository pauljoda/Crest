import Foundation

@MainActor
final class BrowserFaviconSession {
    private let document: any BrowserFaviconDocument
    private let policy: BrowserFaviconCapturePolicy
    private let wait: @MainActor (Duration) async throws -> Void
    private let receive: (Data) -> Void
    private var generation: UInt64 = 0
    private var task: Task<Data?, Never>?
    private var isStopped = false

    init(
        document: any BrowserFaviconDocument,
        policy: BrowserFaviconCapturePolicy = .immediate,
        wait: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        receive: @escaping (Data) -> Void
    ) {
        self.document = document
        self.policy = policy
        self.wait = wait
        self.receive = receive
    }

    deinit { task?.cancel() }

    func invalidate() {
        generation &+= 1
        task?.cancel()
        task = nil
    }

    func stop() {
        isStopped = true
        invalidate()
    }

    func refresh() {
        _ = start()
    }

    func pull() async -> Data? {
        guard !Task.isCancelled, let task = start() else { return nil }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func start() -> Task<Data?, Never>? {
        invalidate()
        guard !isStopped, let url = document.url else { return nil }
        let requestGeneration = generation
        let document = document
        let policy = policy
        let wait = wait
        let task = Task { [weak self] in
            let isCurrent = { [weak self] in
                !Task.isCancelled && self?.generation == requestGeneration && document.url == url
            }
            let data = await Self.load(document, url: url, policy: policy, wait: wait, isCurrent: isCurrent)
            guard isCurrent() else { return nil as Data? }
            self?.task = nil
            if let data { self?.receive(data) }
            return data
        }
        self.task = task
        return task
    }

    private static func load(
        _ document: any BrowserFaviconDocument,
        url: URL,
        policy: BrowserFaviconCapturePolicy,
        wait: @MainActor (Duration) async throws -> Void,
        isCurrent: () -> Bool
    ) async -> Data? {
        guard isCurrent() else { return nil }
        let captured = await document.capture()
        guard isCurrent() else { return nil }
        if let captured { return captured }

        let fallback = await document.fallback(for: url)
        guard isCurrent() else { return nil }
        if let fallback { return fallback }

        for delay in policy.retryDelays {
            do { try await wait(delay) } catch { return nil }
            guard isCurrent() else { return nil }
            let captured = await document.capture()
            guard isCurrent() else { return nil }
            if let captured { return captured }
        }
        return nil
    }
}
