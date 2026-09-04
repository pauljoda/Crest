import SwiftUI

private struct BrowserReadableForegroundModifier: ViewModifier {
    let background: Color

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content.foregroundStyle(
            BrowserVisualAccessibilityPolicy.readableForeground(
                over: background,
                environment: environment
            )
        )
    }
}

private struct BrowserTabResidencyModifier: ViewModifier {
    let isLoaded: Bool

    func body(content: Content) -> some View {
        content
            .saturation(
                BrowserVisualAccessibilityPolicy.tabResidencySaturation(
                    isLoaded: isLoaded
                )
            )
            .opacity(
                BrowserVisualAccessibilityPolicy.tabResidencyOpacity(
                    isLoaded: isLoaded
                )
            )
    }
}

private struct CrestOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier, identifier.contains(where: { !$0.isWhitespace }) {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

private struct CrestOptionalAccessibilityValue: ViewModifier {
    let value: Text?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let value {
            content.accessibilityValue(value)
        } else {
            content
        }
    }
}

extension View {
    func browserReadableForeground(over background: Color) -> some View {
        modifier(BrowserReadableForegroundModifier(background: background))
    }

    /// Fades what stands for a tab the shell is no longer holding in memory.
    ///
    /// Applied to the pieces that *describe* the tab — its favicon, its title —
    /// rather than to the row or tile as a whole, so a mark drawn over one of
    /// them can stay out of the treatment. An unloaded tab still holds its
    /// extension side panel, and the badge saying so keeps full strength.
    func browserTabResidency(isLoaded: Bool) -> some View {
        modifier(BrowserTabResidencyModifier(isLoaded: isLoaded))
    }

    /// Applies an identifier only when one is supplied, preserving any identifier
    /// already published by the wrapped control.
    func crestAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(CrestOptionalAccessibilityIdentifier(identifier: identifier))
    }

    /// Publishes a spoken value only when the component has meaningful detail to
    /// add beyond its accessibility label.
    func crestAccessibilityValue(_ value: Text?) -> some View {
        modifier(CrestOptionalAccessibilityValue(value: value))
    }

    /// Keeps action menus consistent across Apple platforms. Every Crest-authored
    /// menu action supplies an icon when a meaningful symbol, Crest, or logo is
    /// available. Apply this to the action builder *inside* each `Menu` or
    /// `contextMenu`: native menu presentation is a boundary, so styling only the
    /// revealing control does not reliably reach submenu rows on macOS.
    func crestMenuActionLabelStyle() -> some View {
        labelStyle(.titleAndIcon)
    }
}
