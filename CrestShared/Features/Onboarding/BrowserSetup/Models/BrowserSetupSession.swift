import Foundation

/// The session setup would leave, as a window of Crest opens over it, and the
/// image each of its tabs wears.
struct BrowserSetupSession: Equatable {
    let seed: SessionState.Seed
    let images: [UUID: Data]
}
