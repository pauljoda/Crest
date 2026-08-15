import SwiftUI

/// A keyboard-reachable choice card with shared selection, hover, press, and
/// accessibility behavior. Callers own only the card's content.
struct CrestSelectableCard<Content: View>: View {
    let isSelected: Bool
    let accessibilityLabel: Text
    var tint: Color?
    var showsCheckmark = true
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    init(
        isSelected: Bool,
        accessibilityLabel: Text,
        tint: Color? = nil,
        showsCheckmark: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.showsCheckmark = showsCheckmark
        self.action = action
        self.content = content
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: CrestSelectableCardMetrics.contentSpacing) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsCheckmark {
                    checkmark
                }
            }
        }
        .buttonStyle(
            CrestSelectableCardStyle(isSelected: isSelected, tint: tint)
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var checkmark: some View {
        Image(systemName: CrestSelectableCardMetrics.checkmarkSymbol)
            .font(.system(size: CrestSelectableCardMetrics.checkmarkSize))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint ?? CrestBrandTheme.accent)
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
    }
}

#Preview("Selectable Card") {
    CrestSelectableCard(
        isSelected: true,
        accessibilityLabel: Text("Private"),
        action: {}
    ) {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Text("Private").font(CrestTypography.controlTitle)
            Text("Require authentication")
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
        }
    }
    .padding()
    .frame(width: 360)
}
