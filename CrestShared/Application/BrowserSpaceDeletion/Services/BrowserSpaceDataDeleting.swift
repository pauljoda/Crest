/// Erases what the platform and every engine keep for a Space before the core
/// lets the Space go.
@MainActor
protocol BrowserSpaceDataDeleting: AnyObject {
    /// Lets go of the pages of the Space `deletion` names and erases the data
    /// of each profile it erases, which leaves out any profile a Space that
    /// stays browses with.
    func deleteData(for deletion: SpaceDeletionState) async throws
}
