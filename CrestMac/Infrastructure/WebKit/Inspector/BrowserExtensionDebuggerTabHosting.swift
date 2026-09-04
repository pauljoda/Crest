import Foundation

/// The tab-level actions a debugger session performs on its own target.
///
/// `Page.close`, `Target.closeTarget`, and `Page.bringToFront` are tab
/// operations, not engine commands: WebKit's protocol cannot close or select a
/// Crest tab. Routing them through the same coordinator the `tabs` API uses is
/// what keeps a protocol client from reaching a tab the `tabs` API would refuse.
@MainActor
protocol BrowserExtensionDebuggerTabHosting: AnyObject {
    func debuggerActivateTab(for target: BrowserExtensionDebuggerTarget) async throws
    func debuggerCloseTab(for target: BrowserExtensionDebuggerTarget) async throws
}

/// Binds the debugger's tab operations to the extension tab coordinator, so
/// `Page.close` removes a tab exactly the way `tabs.remove` does.
@MainActor
final class BrowserExtensionDebuggerTabCoordinatorHost: BrowserExtensionDebuggerTabHosting {
    private weak var coordinator: BrowserExtensionTabWindowCoordinator?

    init(coordinator: BrowserExtensionTabWindowCoordinator) {
        self.coordinator = coordinator
    }

    func debuggerActivateTab(for target: BrowserExtensionDebuggerTarget) async throws {
        try await perform { coordinator, completion in
            coordinator.activate(tabID: target.tabID, spaceID: target.spaceID, completionHandler: completion)
        }
    }

    func debuggerCloseTab(for target: BrowserExtensionDebuggerTarget) async throws {
        try await perform { coordinator, completion in
            coordinator.close(tabID: target.tabID, spaceID: target.spaceID, completionHandler: completion)
        }
    }

    private func perform(
        _ operation: (BrowserExtensionTabWindowCoordinator, @escaping (Error?) -> Void) -> Void
    ) async throws {
        guard let coordinator else { throw BrowserExtensionDebuggerError.detachedWhileHandling }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation(coordinator) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
