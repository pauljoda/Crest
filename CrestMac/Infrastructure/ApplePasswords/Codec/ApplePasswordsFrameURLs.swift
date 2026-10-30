import Foundation

/// The origins a one-time code query is about: the frame's, then the
/// top-level page's when that differs. Origins only, never a path or a query,
/// and only https ones.
struct ApplePasswordsFrameURLs: Encodable, Equatable, Sendable {
    // MARK: - Variables

    let frame: CredentialOrigin
    let topLevel: CredentialOrigin
    let origins: [String]

    // MARK: - Initializers

    /// - Throws: `insecureOrigin` unless the frame's origin is https. A
    ///   top-level origin that is not https is left out.
    init(frame: CredentialOrigin, topLevel: CredentialOrigin) throws {
        guard frame.isSecure else { throw ApplePasswordsError.insecureOrigin }
        var origins = [frame.description]
        if topLevel != frame, topLevel.isSecure { origins.append(topLevel.description) }
        self.frame = frame
        self.topLevel = topLevel
        self.origins = origins
    }

    // MARK: - Actions - Admission

    /// The codes of `codes` that belong to the frame, as the query asked.
    func admitted(_ codes: [ApplePasswordsOneTimeCode]) -> [ApplePasswordsOneTimeCode] {
        codes.filter { $0.belongs(toFrame: frame, topLevel: topLevel) }
    }

    // MARK: - Actions - Encoding

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(origins)
    }
}
