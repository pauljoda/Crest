import Foundation
import SwiftUI

struct BrowserDownloadRowAction: View {
    let item: DownloadState
    let destinations: [BrowserUtilityDownloadDestination]
    let perform: (BrowserUtilityDownloadAction) -> Void

    var body: some View {
        if item.phase.canRetry {
            actionButton("Allow Download", systemImage: "arrow.clockwise") {
                perform(.retry(item.id))
            }
        } else if item.phase.isLive {
            actionButton("Cancel Download", systemImage: "xmark") {
                perform(.cancel(item.id))
            }
        } else if item.phase.isComplete {
            BrowserDownloadFinishedAction(
                itemID: item.id,
                destinations: destinations,
                perform: perform
            )
        } else {
            actionButton("Remove Download", systemImage: "trash", role: .destructive) {
                perform(.clear(item.id))
            }
        }
    }

    private func actionButton(
        _ title: LocalizedStringResource,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, role: role, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .frame(
                width: BrowserUtilitySwitcherLayout.buttonSize,
                height: BrowserUtilitySwitcherLayout.buttonSize
            )
    }
}

#if DEBUG
    #Preview("Download actions") {
        VStack {
            BrowserDownloadRowAction(
                item: BrowserUtilityListPreviewFixture.activeDownload, destinations: [], perform: { _ in })
            BrowserDownloadRowAction(
                item: BrowserUtilityListPreviewFixture.failedDownload, destinations: [], perform: { _ in })
            BrowserDownloadRowAction(
                item: BrowserUtilityListPreviewFixture.finishedDownload, destinations: [], perform: { _ in })
        }.padding()
    }
#endif
