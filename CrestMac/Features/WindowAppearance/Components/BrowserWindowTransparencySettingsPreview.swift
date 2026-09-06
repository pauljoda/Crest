import SwiftUI

struct BrowserWindowTransparencySettingsPreview: View {
    @Environment(BrowserWindowTransparencyStore.self) private var transparency

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { color in
                        Circle().fill(color).frame(width: 6, height: 6)
                    }
                }
                Label("Space", systemImage: "folder")
                Text("Selected tab")
                    .padding(6)
                    .background(.white.opacity(0.12), in: .rect(cornerRadius: 6))
                Spacer(minLength: 0)
            }
            .font(.system(size: 10))
            .foregroundStyle(.white)
            .padding(10)
            .frame(width: 112)
            BrowserSettingsPagePreview()
                .clipShape(.rect(cornerRadius: 6))
                .padding([.vertical, .trailing], 6)
        }
        .background {
            BrowserSpaceBannerBackground(branding: .init(colors: [.ink], bannerPattern: .solid))
                .opacity(
                    BrowserWindowTransparencyPolicy.baseLayerOpacity(
                        isEnabled: transparency.isEnabled,
                        strength: transparency.strength,
                        isWindowFocused: true))
        }
        .clipShape(.rect(cornerRadius: 10))
        .padding(16)
        .background {
            LinearGradient(colors: [.indigo, .teal, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 12))
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focused window preview")
        .accessibilityIdentifier("window-transparency-preview")
    }
}
