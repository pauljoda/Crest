import Foundation

extension URL {
    // MARK: - Variables

    /// Whether this address is the person's own development work, as the core
    /// answers it: a local file, a single-label host, a private or loopback
    /// address, or a host under a local-only name, so developer mode turns on
    /// by itself.
    var isLocalDevelopmentAddress: Bool {
        let question = LocalDevelopmentAddress(scheme: scheme, host: host(percentEncoded: false))
        return (try? CrestCore.answer(question))?.isLocal ?? false
    }
}
