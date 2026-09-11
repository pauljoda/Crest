import SwiftUI

/// A live miniature of the sidebar and page edge choices.
struct BrowserWindowTransparencySettingsPreview: View {
    var appearance = BrowserChromeAppearance()
    @Environment(BrowserWindowTransparencyStore.self) private var transparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    private var edge: HorizontalEdge { appearance.sidebarEdge(in: layoutDirection) }
    private let sidebarWidth: CGFloat = 104

    var body: some View {
        ZStack(alignment: edge == .leading ? .leading : .trailing) {
            HStack(spacing: 0) {
                Color.clear.frame(width: edge == .leading ? sidebarWidth : 0)
                page
                    .padding(
                        appearance.borderless
                            ? EdgeInsets()
                            : EdgeInsets(
                                top: 6, leading: edge == .leading ? 0 : 6,
                                bottom: 6, trailing: edge == .trailing ? 0 : 6))
                Color.clear.frame(width: edge == .trailing ? sidebarWidth : 0)
            }
            sidebar
                .frame(width: sidebarWidth)
        }
        .frame(height: 190)
        .background {
            BrowserSpaceBannerBackground(branding: .init(colors: [.ink], bannerPattern: .solid))
                .opacity(
                    BrowserWindowTransparencyPolicy.baseLayerOpacity(
                        isEnabled: transparency.isEnabled, strength: transparency.strength, isWindowFocused: true))
        }
        .clipShape(.rect(cornerRadius: 10))
        .padding(16)
        .background {
            LinearGradient(colors: [.indigo, .teal, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .clipShape(.rect(cornerRadius: 12))
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .animation(
            BrowserVisualAccessibilityPolicy.animation(CrestMotion.collection, reduceMotion: reduceMotion),
            value: appearance.sidebarOnRight
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Browser window preview")
        .accessibilityValue(
            Text(
                "\(appearance.sidebarOnRight ? String(localized: "Sidebar on right") : String(localized: "Sidebar on left")), \(appearance.borderless ? String(localized: "Borderless") : String(localized: "Bordered"))"
            )
        )
        .accessibilityIdentifier("window-transparency-preview")
    }

    private var page: some View {
        BrowserSettingsPagePreview(zoom: 0.6)
            .frame(maxHeight: .infinity)
            .background(Color(white: 0.98))
            .clipShape(.rect(cornerRadius: appearance.borderless ? 0 : 6))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach([Color.red, .yellow, .green], id: \.self) { color in
                    Circle().fill(color).frame(width: 6, height: 6)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.left")
                Image(systemName: "chevron.right")
            }
            Label("Space", systemImage: "folder")
            Text("Selected tab")
                .padding(6)
                .background(.white.opacity(0.12), in: .rect(cornerRadius: 6))
            Spacer(minLength: 0)
            Image(systemName: appearance.sidebarOnRight ? "sidebar.right" : "sidebar.left")
        }
        .font(.system(size: 10))
        .foregroundStyle(.white)
        .padding(10)
    }
}
