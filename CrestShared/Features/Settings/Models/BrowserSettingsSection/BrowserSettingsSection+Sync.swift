import Foundation

/// The sections of the Sync settings page.
///
/// iCloud sync, its conflicts, what syncs and diagnostics.
extension BrowserSettingsSection {
    static let iCloud = BrowserSettingsSection(
        name: "iCloud", title: "iCloud",
        searchTerms: "iCloud CloudKit sync now pull from iCloud status account upload download errors")
    static let syncConflict = BrowserSettingsSection(
        name: "syncConflict", title: "Choose which copy to keep",
        searchTerms: "conflict use this device use iCloud")
    static let syncScope = BrowserSettingsSection(
        name: "syncScope", title: "What syncs",
        searchTerms: "Spaces tabs history Crest Passwords cookies website data")
    static let syncDiagnostics = BrowserSettingsSection(
        name: "syncDiagnostics", title: "Diagnostics",
        searchTerms: "diagnostics monitor pending records")
}
