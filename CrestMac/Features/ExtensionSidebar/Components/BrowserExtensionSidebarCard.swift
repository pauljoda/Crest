import SwiftUI

struct BrowserExtensionSidebarCard: View {
    let host: BrowserExtensionSidebarHost
    let panel: BrowserExtensionSidebarPanel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if let icon = host.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "puzzlepiece.extension.fill").frame(width: 16, height: 16)
                }
                if host.availablePanels.count > 1 {
                    Menu {
                        ForEach(host.availablePanels, id: \.clientID) { candidate in
                            Button {
                                host.select(candidate)
                            } label: {
                                if candidate.clientID == panel.clientID {
                                    Label {
                                        Text(verbatim: candidate.title)
                                    } icon: {
                                        Image(systemName: "checkmark")
                                    }
                                } else {
                                    Text(verbatim: candidate.title)
                                }
                            }
                        }
                    } label: {
                        Text(verbatim: panel.title).font(.callout).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Choose Extension Side Panel")
                } else {
                    Text(verbatim: panel.title).font(.callout).lineLimit(1)
                }
                Spacer(minLength: 4)
                Button(action: host.close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24).contentShape(.circle)
                }
                .buttonStyle(BrowserExtensionSidebarCloseButtonStyle())
                .accessibilityLabel("Close Side Panel")
                .help("Close Side Panel")
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            Divider()
            if let error = host.document?.errorDescription {
                ContentUnavailableView {
                    Label("Side Panel Unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(verbatim: error)
                }
            } else if let webView = host.document?.webView {
                BrowserExtensionSidebarWebView(webView: webView, userInteracted: host.userInteracted)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Extension side panel: \(panel.title)"))
    }
}

private struct BrowserExtensionSidebarCloseButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.08 : 0), in: Circle())
            .onHover { isHovering = $0 }
    }
}
