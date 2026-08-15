extension TabPlacement {
    static func < (lhs: TabPlacement, rhs: TabPlacement) -> Bool {
        lhs.durability < rhs.durability
    }

    static func max(_ lhs: TabPlacement, _ rhs: TabPlacement) -> TabPlacement {
        lhs < rhs ? rhs : lhs
    }

    var durability: Int {
        switch self {
        case .current: 0
        case .saved: 1
        case .pinned: 2
        }
    }

    var sortIndex: Int {
        switch self {
        case .pinned: 0
        case .saved: 1
        case .current: 2
        }
    }
}
