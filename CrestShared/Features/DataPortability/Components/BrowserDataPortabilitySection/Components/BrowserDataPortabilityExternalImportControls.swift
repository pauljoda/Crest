import SwiftUI

struct BrowserDataPortabilityExternalImportControls: View {
    let model: BrowserDataPortabilityModel

    var body: some View {
        Menu("Import Bookmarks…", systemImage: "square.and.arrow.down.on.square") {
            ForEach(BrowserBookmarkMigrationSource.allCases) { source in
                Button(source.title, systemImage: source.symbol) {
                    model.beginBookmarkImport(from: source)
                }
            }
        }
        .accessibilityIdentifier("import-bookmarks")

        Menu("Import History…", systemImage: "clock.arrow.circlepath") {
            ForEach(BrowserHistoryMigrationSource.allCases) { source in
                Button(source.title, systemImage: source.symbol) {
                    model.beginHistoryImport(from: source)
                }
            }
        }
        .accessibilityIdentifier("import-history")

        Menu("Import Open Tabs…", systemImage: "rectangle.stack.badge.plus") {
            ForEach(BrowserTabMigrationSource.allCases) { source in
                Button(source.title, systemImage: source.symbol) {
                    model.beginTabImport(from: source)
                }
            }
        }
        .accessibilityIdentifier("import-open-tabs")
    }
}
