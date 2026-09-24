import Foundation
import SwiftUI

struct BrowserDownloadRowAction: View {
    let item: DownloadState
    let destinations: [BrowserUtilityDownloadDestination]
    let perform: (BrowserUtilityDownloadAction) -> Void

    /// The phase chooses the action; this is the one place that turns each
    /// kind into the command the platform performs.
    var body: some View {
        let action = item.phase.primaryAction
        switch action.kind {
        case .retry:
            actionButton(action) { perform(.retry(item.id)) }
        case .cancel:
            actionButton(action) { perform(.cancel(item.id)) }
        case .open:
            BrowserDownloadFinishedAction(
                itemID: item.id,
                action: action,
                destinations: destinations,
                perform: perform
            )
        case .remove:
            actionButton(action) { perform(.clear(item.id)) }
        }
    }

    private func actionButton(
        _ action: DownloadRowAction,
        perform: @escaping () -> Void
    ) -> some View {
        Button(
            action.title,
            systemImage: action.symbol,
            role: action.isDestructive ? .destructive : nil,
            action: perform
        )
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
