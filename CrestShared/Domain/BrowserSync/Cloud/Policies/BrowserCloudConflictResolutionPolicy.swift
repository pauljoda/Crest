enum BrowserCloudConflictResolutionPolicy {
    static func shouldMergeFetchedContent(
        resolution: BrowserCloudConflictResolution?
    ) -> Bool {
        resolution != .useThisDevice
    }

    static func resolutionAfterRestart(
        persistedResolution: BrowserCloudConflictResolution?,
        hasPendingUploads: Bool
    ) -> BrowserCloudConflictResolution? {
        guard persistedResolution == .useThisDevice,
            !hasPendingUploads
        else { return persistedResolution }
        return nil
    }
}
