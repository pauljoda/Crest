enum BrowserStoreSyncStageUrgency {
    case coalesced
    case immediate
}

struct BrowserStoreSyncRevision: Comparable, Sendable {
    static let initial = BrowserStoreSyncRevision(value: 0)

    private let value: UInt64

    func successor() -> BrowserStoreSyncRevision {
        precondition(value < UInt64.max, "Browser store sync revision exhausted")
        return BrowserStoreSyncRevision(value: value + 1)
    }

    static func < (
        lhs: BrowserStoreSyncRevision,
        rhs: BrowserStoreSyncRevision
    ) -> Bool {
        lhs.value < rhs.value
    }
}
