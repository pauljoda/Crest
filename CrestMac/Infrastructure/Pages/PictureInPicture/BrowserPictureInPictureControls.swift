import SwiftUI

struct BrowserPictureInPictureControls: View {
    let isPlaying: Bool
    let playPause: () -> Void
    let restore: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            control("Close", symbol: "xmark", action: close)
            if isPlaying {
                control("Pause", symbol: "pause.fill", action: playPause)
            } else {
                control("Play", symbol: "play.fill", action: playPause)
            }
            control("Return to Tab", symbol: "pip.exit", action: restore)
        }
        .padding(CrestSpacing.extraSmall)
        .crestGlass(in: Capsule())
        .environment(\.colorScheme, .dark)
        .fixedSize()
    }

    private func control(_ title: LocalizedStringResource, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .accessibilityLabel(Text(title))
        }
        .buttonStyle(CrestChromeButtonStyle.circle())
        .help(String(localized: title))
    }
}
