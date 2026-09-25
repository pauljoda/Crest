import Foundation

extension CoreState {
    /// A Space that keeps no choices leaves the map. Every change advances the
    /// revision, since a session choice changes decisions without changing a
    /// kept record.
    func apply(_ change: SitePermissionsChanged) {
        sitePermissions[change.spaceID] = change.records.isEmpty ? nil : change.records
        sitePermissionRevision &+= 1
    }
}
