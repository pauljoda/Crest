import Foundation
import SwiftUI

struct BrowserDownloadRowAction: View {
    let item: BrowserDownloadItem
    let destinations: [BrowserUtilityDownloadDestination]
    let perform: (BrowserUtilityDownloadAction) -> Void

    var body: some View {
        switch item.state {
        case .blockedAutomaticDownload:
            actionButton("Allow Download", systemImage: "arrow.clockwise") {
                perform(.retry(item.id))
            }
        case .preparing, .awaitingApproval, .downloading:
            actionButton("Cancel Download", systemImage: "xmark") {
                perform(.cancel(item.id))
            }
        case .finished:
            BrowserDownloadFinishedAction(
                itemID: item.id,
                destinations: destinations,
                perform: perform
            )
        case .canceled, .failed:
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
