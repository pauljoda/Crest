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
    /// The targets in `spaceID` a debugger currently holds.
    ///
    /// The store knows its own sessions and nothing about which tabs exist, so
    /// this reports attachment state and leaves enumeration to the caller that
    /// owns the Space's tab list. Chrome's `getTargets` does not prompt, so an
    /// ungranted client is refused rather than asked.
    func getTargets(
        in spaceID: SpaceID, for client: BrowserExtensionServiceClientID
    ) throws -> Set<BrowserExtensionDebuggerTarget>
    func events(for client: BrowserExtensionServiceClientID) -> AsyncStream<BrowserExtensionDebuggerEvent>
    func reconcileTargets()
}
