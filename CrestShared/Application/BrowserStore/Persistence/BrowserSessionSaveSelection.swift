/// Which members of a keyed store one save covers.
enum BrowserSessionSaveSelection<Identifier: Hashable & Sendable>: Equatable, Sendable {
    case nothing
    case only(Set<Identifier>)
    case everything

    func covers(_ identifier: Identifier) -> Bool {
        switch self {
        case .nothing:
            false
        case .only(let identifiers):
            identifiers.contains(identifier)
        case .everything:
            true
        }
    }

    var isEverything: Bool {
        self == .everything
    }
}
