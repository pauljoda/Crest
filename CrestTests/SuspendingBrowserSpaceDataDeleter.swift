@testable import Crest

@MainActor
final class SuspendingBrowserSpaceDataDeleter: BrowserSpaceDataDeleting {
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var deletionContinuation: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func deleteData(for space: BrowserSpace) async throws {
        hasStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            deletionContinuation = continuation
        }
    }

    func waitUntilDeletionStarts() async {
        guard !hasStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func finishDeletion() {
        deletionContinuation?.resume()
        deletionContinuation = nil
    }
}
