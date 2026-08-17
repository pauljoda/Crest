import SwiftUI

struct BrowserCrestImportPreview: View {
    let space: BrowserSpace?
    let sourceName: String
    var isSpaceIncluded = true
    var matchedTabIDs: Set<TabID> = []

    var body: some View {
        if !isSpaceIncluded {
            BrowserImportSidebarFrame(
                branding: .neutralImport(symbol: "rectangle.stack.badge.minus")
            ) {
                ContentUnavailableView(
                    "Space Skipped",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("Turn on Move Space to include it in this import.")
                )
            }
            .accessibilityLabel("Space skipped")
        } else if let space {
            BrowserImportSidebarFrame(branding: space.branding) {
                BrowserCrestImportContent(
                    space: space,
                    matchedTabIDs: matchedTabIDs
                )
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Crest \(space.name) sidebar after import")
        } else {
            BrowserImportSidebarFrame(
                branding: .neutralImport(symbol: "square.grid.2x2")
            ) {
                ContentUnavailableView(
                    "Preview Unavailable",
                    systemImage: "rectangle.stack.badge.minus",
                    description: Text("Crest could not build this \(sourceName) Space preview.")
                )
            }
        }
    }
}
