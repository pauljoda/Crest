import Foundation

/// A move through a tab's history an agent asks for, as the navigate tool
/// spells it, and how the tab's page makes it.
struct BrowserAgentNavigationAction: Decodable, Sendable {
    // MARK: - Static Variables

    static let back = Self(name: "back") { $0.goToHistory(offset: -1) }
    static let forward = Self(name: "forward") { $0.goToHistory(offset: 1) }
    static let reload = Self(name: "reload") { $0.reload() }

    static let all: [BrowserAgentNavigationAction] = [back, forward, reload]

    // MARK: - Variables

    let name: String
    private let move: @MainActor @Sendable (EnginePage) -> Void

    // MARK: - Initializers

    private init(name: String, move: @escaping @MainActor @Sendable (EnginePage) -> Void) {
        self.name = name
        self.move = move
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let action = Self.all.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Crest has no navigation action \(name).")
        }
        self = action
    }

    // MARK: - Actions - Navigation

    /// Makes the move on the tab's engine page.
    @MainActor
    func perform(on page: EnginePage) {
        move(page)
    }
}
