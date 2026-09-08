enum BrowserDownloadRetryRegistrationPolicy {
    nonisolated static func shouldRegister(
        lease: BrowserDownloadRetryLease,
        currentLease: BrowserDownloadRetryLease?,
        item: BrowserDownloadItem?,
        contextAssignment: BrowserSpaceRuntimeAssignment?,
        isAssignmentAvailable: Bool
    ) -> Bool {
        currentLease == lease
            && contextAssignment == lease.assignment
            && isAssignmentAvailable
            && item?.id == lease.itemID
            && item?.profileID == lease.assignment.profileID
            && item?.state == .preparing
    }
}
