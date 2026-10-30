import Foundation

/// A byte pipe to a running helper: whole frames in, whole frames out. The
/// process is the real one; tests stand in a fake.
protocol ApplePasswordsChannel: Sendable {
    /// What the helper sends, ending with `closed` once the pipe is gone.
    var events: AsyncStream<ApplePasswordsChannelEvent> { get }

    /// Writes one frame's payload. Throws if the helper is no longer there to read it.
    func send(_ payload: Data) throws
    /// Ends the helper, if it still runs.
    func terminate()
}

enum ApplePasswordsChannelEvent: Sendable {
    /// One frame's payload, whole.
    case frame(Data)
    /// The helper is gone, or sent something the protocol does not allow.
    case closed(ApplePasswordsUnavailability)
}

/// Starts a helper and returns the channel to it.
protocol ApplePasswordsChannelLauncher: Sendable {
    func launch() throws -> any ApplePasswordsChannel
}
