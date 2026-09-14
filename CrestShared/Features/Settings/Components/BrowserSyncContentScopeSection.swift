import SwiftUI

struct BrowserSyncContentScopeSection: View {
    var body: some View {
        Section("What Syncs") {
            SyncSettingsFactRow(
                title: "Spaces and browser content",
                detail:
                    "Space identity, pinned and saved tabs, current tabs, history, and archive records sync through Crest’s private CloudKit database.",
                symbol: "square.stack.3d.up.fill"
            )
            SyncSettingsFactRow(
                title: "Crest Passwords",
                detail:
                    "Password values never enter CloudKit. Each Space’s separate iCloud Keychain switch controls those encrypted Keychain items.",
                symbol: "key.fill"
            )
            SyncSettingsFactRow(
                title: "Device-only data",
                detail:
                    "Cookies, website data, service workers, downloads, and active page state stay on this device and remain isolated by Space.",
                symbol: "internaldrive.fill"
            )
        }
    }
}
