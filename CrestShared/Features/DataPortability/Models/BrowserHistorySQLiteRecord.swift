struct BrowserHistorySQLiteRecord: Sendable {
    let url: String
    let title: String
    let firstVisit: Double
    let lastVisit: Double
    let visitCount: Int
}
