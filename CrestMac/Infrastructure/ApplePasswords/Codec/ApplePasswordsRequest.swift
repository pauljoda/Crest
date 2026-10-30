import Foundation

/// A message Crest sends and the reply that answers it. Each request encodes
/// itself and reads its own reply, so the queue never looks at a payload.
protocol ApplePasswordsRequest: Sendable {
    associatedtype Reply: Sendable

    var command: ApplePasswordsCommand { get }
    /// How long the helper may take before the request counts as unanswered.
    var timeout: Duration { get }

    /// What the request means when the helper never acknowledges it within
    /// `timeout`, or nil when silence is a failure that ends the session.
    /// A request that tolerates silence must have an acknowledgement that
    /// carries no data, because a late one is swallowed.
    var silentReply: Reply? { get }

    /// The JSON the frame carries.
    func encoded() throws -> Data
    /// Whether a reply with this request's command may answer it. A reply that
    /// does not is dropped and the request keeps waiting.
    func accepts(_ envelope: ApplePasswordsInboundEnvelope) -> Bool
    /// What the reply means, or why it is not acceptable.
    func reply(from envelope: ApplePasswordsInboundEnvelope) throws -> Reply
}

extension ApplePasswordsRequest {
    var timeout: Duration { .seconds(5) }
    func accepts(_ envelope: ApplePasswordsInboundEnvelope) -> Bool { true }
    var silentReply: Reply? { nil }
}
