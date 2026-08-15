struct BrowserUtilityListSection: Identifiable, Sendable {
    let timeframe: BrowserUtilityTimeSection
    let items: [BrowserUtilityListItem]

    var id: String { timeframe.id }
}
