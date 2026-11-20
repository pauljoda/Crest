import SwiftUI

/// A scope's chip: its symbol and name in Crest blue.
struct BrowserPaletteScopeChip: View {
    let scope: PaletteScope
    var showsCloseControl = false
    var isInteractive = false

    var body: some View {
        BrowserPaletteChip(
            color: CrestBrandTheme.accent, showsCloseControl: showsCloseControl, isInteractive: isInteractive
        ) {
            Image(systemName: scope.symbol)
                .font(.caption.weight(.semibold))
            Text(scope.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
    }
}

/// The capsule a palette chip draws its contents in: a layer of the palette's
/// material filled with `color`, under contents in white or black, whichever
/// the text tone a Space's colors use reads better over `color`. A chip a
/// person can click is `isInteractive`, so it answers the pointer.
struct BrowserPaletteChip<Content: View>: View {
    let color: Color
    let showsCloseControl: Bool
    var isInteractive = false
    @ViewBuilder let content: Content

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            content
            if showsCloseControl {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundStyle(color.perceptualForeground(in: colorScheme))
        .padding(.horizontal, CrestSpacing.small)
        .padding(.vertical, CrestSpacing.extraSmall)
        .background {
            CrestSurfaceLayer(
                shape: Capsule(), tint: color, hoverTint: isInteractive && isHovering ? CrestColor.hover : nil)
        }
        .onHover { isHovering = $0 }
    }
}
