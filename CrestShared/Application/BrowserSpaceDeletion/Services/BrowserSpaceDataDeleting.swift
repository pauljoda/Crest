@MainActor
protocol BrowserSpaceDataDeleting: AnyObject {
    func deleteData(for space: BrowserSpace) async throws
}
