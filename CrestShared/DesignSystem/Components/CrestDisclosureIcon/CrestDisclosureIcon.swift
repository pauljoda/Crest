import SwiftUI

/// An icon slot that wears its content while what it heads is open, and a
/// chevron while it is collapsed.
///
/// The change is one motion: collapsing turns a chevron from pointing down to
/// pointing at the title as it fades in over the fading content, and expanding
/// turns it back down as it fades out under the returning content. With Reduce
/// Motion the two only fade.
struct CrestDisclosureIcon<Content: View>: View {
    // MARK: - Variables

    let isCollapsed: Bool
    /// The chevron's point size.
    let glyphSize: CGFloat
    var glyphWeight: Font.Weight = .bold
    @ViewBuilder let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Initializers

    init(
        isCollapsed: Bool, glyphSize: CGFloat, glyphWeight: Font.Weight = .bold, @ViewBuilder content: () -> Content
    ) {
        self.isCollapsed = isCollapsed
        self.glyphSize = glyphSize
        self.glyphWeight = glyphWeight
        self.content = content()
    }

    // MARK: - Actions - Drawing

    var body: some View {
        // Both stay in place, so the chevron can turn while either fades.
        ZStack {
            content
                .opacity(isCollapsed ? 0 : 1)
                .accessibilityHidden(isCollapsed)
            Image(systemName: "chevron.right")
                .font(.system(size: glyphSize, weight: glyphWeight))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isCollapsed || reduceMotion ? 0 : 90))
                .opacity(isCollapsed ? 1 : 0)
                .accessibilityHidden(true)
        }
        // Under Reduce Motion the chevron stays still, so this is a fade.
        .animation(CrestMotion.disclosure, value: isCollapsed)
    }
}

#if DEBUG
    #Preview("Disclosure icon") {
        @Previewable @State var isCollapsed = false
        VStack(spacing: CrestSpacing.large) {
            CrestDisclosureIcon(isCollapsed: isCollapsed, glyphSize: 12) {
                Image(systemName: "folder.fill").foregroundStyle(.tint)
            }
            .frame(width: 24, height: 24)
            Toggle("Collapsed", isOn: $isCollapsed)
        }
        .padding(32)
    }
#endif
