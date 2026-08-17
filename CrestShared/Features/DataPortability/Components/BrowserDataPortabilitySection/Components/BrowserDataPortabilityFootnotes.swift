import SwiftUI

struct BrowserDataPortabilityFootnotes: View {
    let showsExternalBrowserImportControls: Bool

    var body: some View {
        Text(
            "Exports Spaces, folders, saved and current tabs, Archive, history, and browsing preferences. Passwords, cookies, website storage, permissions, downloads, favicons, and extensions are never included."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("browser-data-exclusions")

        if showsExternalBrowserImportControls {
            Text(
                "Bookmark HTML includes pinned and saved sites only. Imports from standard HTML, Safari, Chrome or Chromium, Firefox, and Arc always create fresh, isolated Crest Spaces."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("bookmark-import-formats")

            Text(
                "History import accepts a copied Safari History.db, Chrome or Arc History database, or Firefox places.sqlite. Quit the source browser before copying; Crest imports up to 5,000 recent entries."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("history-import-formats")

            Text(
                "Open-tab import accepts a copied Safari session property list, cleartext Chrome or Chromium Session_* file, Firefox recovery.jsonlz4 or sessionstore.jsonlz4, or Arc StorableSidebar.json. Each source window becomes a fresh, isolated Crest Space; profile-encrypted Chromium sessions cannot be imported."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("tab-import-formats")
        }
    }
}
