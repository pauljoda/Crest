import Foundation

extension ContentBlockingPolicy {
    // MARK: - Actions - Switching

    /// The policy a Space's blocking switch moves to: one that blocks when this
    /// one blocks nothing, and one that blocks nothing when this one blocks.
    var switched: ContentBlockingPolicy {
        Self.all.first { $0.blocksContent != blocksContent } ?? self
    }

    /// The policy that blocks, or does not, as a switch asks.
    static func blocking(_ blocks: Bool) -> ContentBlockingPolicy {
        guard let policy = all.first(where: { $0.blocksContent == blocks }) else {
            preconditionFailure("The core offers a policy that blocks and one that does not.")
        }
        return policy
    }
}
