import Foundation

/// Owns one decision while bounding the callbacks an extension can retain.
/// Busy or expired requests fail without changing the person's saved decisions.
@MainActor
final class BrowserExtensionPermissionPromptController {
    enum Decision: Equatable { case allow, deny, cancel }
    struct Key: Equatable {
        let context: ObjectIdentifier
        let tab: TabID?
        let access: [String]
    }
    typealias Present = (@escaping (Decision) -> Void) -> (() -> Void)

    private struct Pending {
        let id: UUID
        let key: Key
        let isValid: () -> Bool
        var completions: [(Decision) -> Void]
        var dismiss: () -> Void = {}
    }
    private struct Queued {
        let key: Key
        let isValid: () -> Bool
        var completions: [(Decision) -> Void]
        let present: Present
    }
    private var queue: [Queued] = []
    private var pending: Pending?
    private var deadline: Task<Void, Never>?
    private let maximumWaiters: Int

    init(maximumWaiters: Int = 32) {
        self.maximumWaiters = maximumWaiters
    }

    isolated deinit {
        deadline?.cancel()
        let active = pending
        pending = nil
        active?.dismiss()
        for completion in active?.completions ?? [] { completion(.cancel) }
        for completion in queue.flatMap(\.completions) { completion(.cancel) }
    }

    func request(
        key: Key, isValid: @escaping () -> Bool, completion: @escaping (Decision) -> Void,
        present: @escaping Present
    ) {
        guard isValid() else {
            completion(.cancel)
            advanceQueue()
            return
        }
        if let active = pending {
            if active.key == key {
                guard active.completions.count < maximumWaiters else {
                    completion(.cancel)
                    return
                }
                pending?.completions.append(completion)
                return
            }
            if let index = queue.firstIndex(where: { $0.key == key }) {
                guard queue[index].completions.count < maximumWaiters else {
                    completion(.cancel)
                    return
                }
                queue[index].completions.append(completion)
                return
            }
            guard queue.count < 8 else {
                completion(.cancel)
                return
            }
            queue.append(Queued(key: key, isValid: isValid, completions: [completion], present: present))
            return
        }
        start(Queued(key: key, isValid: isValid, completions: [completion], present: present))
    }

    private func start(_ request: Queued) {
        let id = UUID()
        pending = Pending(id: id, key: request.key, isValid: request.isValid, completions: request.completions)
        let dismiss = request.present { [weak self] decision in self?.finish(id: id, decision: decision) }
        guard pending?.id == id else {
            dismiss()
            return
        }
        pending?.dismiss = dismiss
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(25)) } catch { return }
            self?.finish(id: id, decision: .cancel)
        }
    }

    func reconcile() {
        let invalid = queue.filter { !$0.isValid() }
        queue.removeAll { !$0.isValid() }
        for completion in invalid.flatMap(\.completions) { completion(.cancel) }
        guard let active = pending, !active.isValid() else { return }
        finish(id: active.id, decision: .cancel)
    }

    func cancel(context: ObjectIdentifier) {
        let canceled = queue.filter { $0.key.context == context }
        queue.removeAll { $0.key.context == context }
        for completion in canceled.flatMap(\.completions) { completion(.cancel) }
        guard let active = pending, active.key.context == context else { return }
        finish(id: active.id, decision: .cancel)
    }

    private func finish(id: UUID, decision: Decision) {
        guard let active = pending, active.id == id else { return }
        let result = active.isValid() ? decision : .cancel
        pending = nil
        deadline?.cancel()
        deadline = nil
        active.dismiss()
        for completion in active.completions { completion(result) }
        advanceQueue()
    }

    private func advanceQueue() {
        guard pending == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        guard next.isValid() else {
            for completion in next.completions { completion(.cancel) }
            advanceQueue()
            return
        }
        start(next)
    }
}
