import SwiftUI

struct BrowserDataPortabilityExportControls: View {
    let model: BrowserDataPortabilityModel

    var body: some View {
        if model.lockedSpaces.isEmpty {
            Button("Export Browser Data…", systemImage: "square.and.arrow.up") {
                model.prepareExport()
            }
            .disabled(model.isPreparingExport)
            .accessibilityIdentifier("export-browser-data")
        } else {
            Text(
                "Unlock every private Space before exporting browser data or bookmarks that include its tabs and history."
            )
            .crestFormFootnote()

            ForEach(model.lockedSpaces) { space in
                BrowserSettingsPrivateSpaceAccessRow(
                    space: space,
                    accessController: model.spaceAccess
                )
            }
        }

        Button("Import Browser Data…", systemImage: "square.and.arrow.down") {
            model.beginPortableImport()
        }
        .accessibilityIdentifier("import-browser-data")

        if model.lockedSpaces.isEmpty {
            Button("Export Bookmarks as HTML…", systemImage: "book.closed") {
                model.prepareBookmarkExport()
            }
            .disabled(model.isPreparingBookmarkExport)
            .accessibilityIdentifier("export-bookmarks-html")
        }
    }
}
