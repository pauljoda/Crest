import Foundation

/// A kind of window an agent may ask to open, and how the person is asked
/// about it: the question, which names the agent, and the line under it,
/// which names the Space and the address where the agent gives them.
struct BrowserAgentWindowKind: Equatable, Sendable {
    // MARK: - Static Variables

    static let window = Self(
        name: "window", asking: { String(localized: "Let “\($0)” open a window?") },
        describing: Self.spaceAndAddress)
    static let blankWindow = Self(
        name: "blank", asking: { String(localized: "Let “\($0)” open a Blank Window?") },
        describing: Self.spaceAndAddress)
    static let quickWindow = Self(
        name: "quick", asking: { String(localized: "Let “\($0)” open a Quick Window?") },
        describing: Self.spaceAndAddress)
    static let privateWindow = Self(
        name: "private", asking: { String(localized: "Let “\($0)” open a private window?") },
        describing: { _, address in
            address.map { String(localized: "It opens \($0). Agents never reach into a private window.") }
                ?? String(localized: "Agents never reach into a private window.")
        })

    // MARK: - Variables

    let name: String
    private let asking: @Sendable (String) -> String
    private let describing: @Sendable (_ space: String?, _ address: String?) -> String?

    // MARK: - Initializers

    private init(
        name: String, asking: @escaping @Sendable (String) -> String,
        describing: @escaping @Sendable (String?, String?) -> String?
    ) {
        self.name = name
        self.asking = asking
        self.describing = describing
    }

    // MARK: - Actions - Questions

    /// The question that asks the person whether the agent `agent` may open
    /// one.
    func question(naming agent: String) -> String {
        asking(agent)
    }

    /// The line under the question, for one over the Space named `space` at
    /// `address`, or nil when there is nothing to add.
    func detail(space: String?, address: String?) -> String? {
        describing(space, address)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    private static func spaceAndAddress(_ space: String?, _ address: String?) -> String? {
        switch (space, address) {
        case (let space?, let address?): String(localized: "It opens \(address) in the \(space) Space.")
        case (let space?, nil): String(localized: "It opens over the \(space) Space.")
        case (nil, _): nil
        }
    }
}
