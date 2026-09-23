import Foundation

/// Transfers an engine runs through Crest's own download path rather than
/// reporting them as `BrowserEngineDownloadUpdate`s. The download center keeps
/// the ledger and feedback; a transport owns the engine's download objects and
/// reports their progress into that ledger.
@MainActor
protocol BrowserDownloadTransport: AnyObject {
    /// Cancels the item's transfer; false when this transport does not run it.
    func cancel(_ itemID: UUID) -> Bool
    /// True while this transport still runs the item's transfer.
    func isTransferring(_ itemID: UUID) -> Bool
    /// Forgets what this transport kept for an item the ledger no longer has.
    func forget(_ itemID: UUID)
    /// Cancels and forgets every transfer that belongs to one Space's profile.
    func removeTransfers(in assignment: BrowserSpaceRuntimeAssignment)
    func setCredentialStorageEnabled(_ isEnabled: Bool, in spaceID: SpaceID)
    /// Starts a new automatic-download sequence for the page whose native view
    /// is `pageView`.
    func resetAutomaticDownloadSequence(forPageView pageView: ObjectIdentifier)
    /// Retries a blocked automatic download, or nil when this transport has
    /// no way to replay it.
    func retryAutomaticDownload(
        _ itemID: UUID,
        matching assignment: BrowserSpaceRuntimeAssignment,
        isAssignmentAvailable: @escaping @MainActor (BrowserSpaceRuntimeAssignment) -> Bool
    ) async -> Bool?
}
