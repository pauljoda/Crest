@MainActor
final class BrowserSettingsPreviewDataDeleter: BrowserSpaceDataDeleting {
    func deleteData(for space: BrowserSpace) async throws {}
}
