import SwiftUI

/// The extension side panel as a card in the page row: a compact header the
/// core owns, and the engine's panel view below it.
struct BrowserExtensionSidePanelCard: View {
    // MARK: - Static Variables

    static let closeDiameter: CGFloat = 24

    // MARK: - Variables

    let host: BrowserExtensionSidePanelHost
    let panel: BrowserExtensionSidePanelHost.Panel

    // MARK: - Actions - Drawing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let icon = panel.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "puzzlepiece.extension.fill").frame(width: 16, height: 16)
                }
                Text(verbatim: panel.title).font(.callout).lineLimit(1)
                Spacer(minLength: 4)
                Button(action: host.close) {
                    Image(systemName: "xmark").font(CrestTypography.metadata.weight(.semibold))
                }
                .buttonStyle(CrestChromeButtonStyle.circle(diameter: BrowserExtensionSidePanelCard.closeDiameter))
                .accessibilityLabel("Close Side Panel")
                .help("Close Side Panel")
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            Divider()
            BrowserExtensionSidePanelSurface(view: panel.view)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Extension side panel: \(panel.title)"))
    }
}

/// Mounts the engine's panel view. The panel is not a page, so it uses the
/// plain AppKit host rather than the page surface's focus and ownership rules.
private struct BrowserExtensionSidePanelSurface: NSViewRepresentable {
    let view: NSView

    func makeNSView(context: Context) -> BrowserWebHostView {
        let host = BrowserWebHostView()
        host.attach(view)
        return host
    }

    func updateNSView(_ host: BrowserWebHostView, context: Context) {
        host.attach(view)
    }

    static func dismantleNSView(_ host: BrowserWebHostView, coordinator: Void) {
        host.detach()
    }
}
