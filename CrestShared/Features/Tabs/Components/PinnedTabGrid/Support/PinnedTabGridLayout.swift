enum PinnedTabGridLayout {
    static let maximumColumns = 4

    static func columnCount(for itemCount: Int) -> Int {
        switch max(1, itemCount) {
        case 1...4:
            return max(1, itemCount)
        case 5...6, 9:
            return 3
        default:
            return maximumColumns
        }
    }
}
