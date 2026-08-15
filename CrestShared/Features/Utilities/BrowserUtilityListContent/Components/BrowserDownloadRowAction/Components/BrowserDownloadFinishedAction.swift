import Foundation
import SwiftUI

struct BrowserDownloadFinishedAction: View {
    let itemID: UUID
    let destinations: [BrowserUtilityDownloadDestination]
    let perform: (BrowserUtilityDownloadAction) -> Void

    var body: some View {
        if destinations.count == 1, let destination = destinations.first {
            Button(destination.title, systemImage: destination.systemImage) {
                perform(.open(itemID, destination))
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserUtilitySwitcherLayout.buttonSize,
                height: BrowserUtilitySwitcherLayout.buttonSize
            )
        } else if !destinations.isEmpty {
            Menu("Export Download", systemImage: "square.and.arrow.up") {
                ForEach(destinations) { destination in
                    Button(destination.title, systemImage: destination.systemImage) {
                        perform(.open(itemID, destination))
                    }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserUtilitySwitcherLayout.buttonSize,
                height: BrowserUtilitySwitcherLayout.buttonSize
            )
        }
    }
}

#Preview("Finished Download Action", traits: .fixedLayout(width: 96, height: 64)) {
    BrowserDownloadFinishedAction(
        itemID: BrowserUtilityListPreviewFixture.finishedDownload.id,
        destinations: [.revealInFinder, .files],
        perform: { _ in }
    )
    .padding()
}
