import Foundation

@MainActor
protocol BrowserExtensionDebuggerHandling: AnyObject {
    func register(client: BrowserExtensionServiceClientID, spaceID: SpaceID, displayName: String)
    func unregister(client: BrowserExtensionServiceClientID)
    func attach(
        to target: BrowserExtensionDebuggerTarget, for client: BrowserExtensionServiceClientID,
        requiredVersion: String
    ) async throws
    func detach(from target: BrowserExtensionDebuggerTarget, for client: BrowserExtensionServiceClientID) throws
    func sendCommand(
        _ command: BrowserExtensionDebuggerCommand, to target: BrowserExtensionDebuggerTarget,
        for client: BrowserExtensionServiceClientID
    ) async throws -> Data
    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionDebuggerEvent>
    func reconcileTargets()
}
