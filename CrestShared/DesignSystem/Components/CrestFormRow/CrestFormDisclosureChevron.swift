import SwiftUI

/// Direction-aware disclosure indicator for a row that navigates or presents,
/// or that opens in place.
struct CrestFormDisclosureChevron: View {
    // MARK: - Variables

    /// Whether the row opens in place and is open now, which turns the
    /// chevron down; a row that navigates or presents leaves it closed.
    var isExpanded = false

    @Environment(\.layoutDirection) private var layoutDirection

    /// Forward while closed and down once open, whichever way the language
    /// reads.
    private var rotation: Angle {
        guard isExpanded else { return .zero }
        return .degrees(layoutDirection == .rightToLeft ? -90 : 90)
    }

    // MARK: - Actions - Drawing

    var body: some View {
        Image(systemName: "chevron.forward")
            .font(CrestTypography.metadata.weight(.semibold))
            .foregroundStyle(.tertiary)
            .rotationEffect(rotation)
            .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Component") {
        HStack {
            CrestFormDisclosureChevron()
            CrestFormDisclosureChevron(isExpanded: true)
        }
        .padding()
    }
#endif
