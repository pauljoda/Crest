import SwiftUI

struct BrowserMirroredPageContent: View {
    let tabID: UUID
    let pages: BrowserPagePool

    var body: some View {
        ZStack {
            if let snapshot = pages.mirroredPageSnapshot(for: tabID) {
                Image(nsImage: snapshot)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 12)
                    .accessibilityHidden(true)
            }
            // The most see-through of Crest's surface materials, whatever the
            // device's choice, so the page under it still shows as the page.
            Rectangle().fill(CrestSurfaceMaterial.ultraThin.material)
            Button {
                pages.claimPresentedPage(for: tabID)
            } label: {
                Label("Active in another window", systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                    .padding(20)
                    .background { CrestSurfaceLayer(shape: .rect(cornerRadius: CrestRadius.control)) }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Move this page here without reloading it.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { pages.claimPresentedPage(for: tabID) }
    }
}
