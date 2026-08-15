/// Website-access grants that could not be rebuilt from a stored permission
/// snapshot. Restoring stays non-fatal, so this is reported against the
/// extension rather than thrown.
struct BrowserExtensionPermissionRestoreError: Error, Equatable {
    let droppedHostPatterns: [String]
}
