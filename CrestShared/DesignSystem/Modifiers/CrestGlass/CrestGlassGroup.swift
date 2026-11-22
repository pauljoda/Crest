import SwiftUI

/// Controls on ``CrestGlassSurface`` that sit together: one container of
/// glass where the system draws it, so neighbouring pieces blend and morph as
/// glass does. Before macOS 26 each control draws its own material, so the
/// group is only its content.
struct CrestGlassGroup<Content: View>: View {
    // MARK: - Variables

    var spacing: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
