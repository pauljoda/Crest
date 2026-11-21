import SwiftUI

struct CrestButtonSurface: View {
    // MARK: - Variables

    let role: CrestButtonRole
    let tint: Color?
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlSize) private var controlSize
    @State private var isHovering = false

    /// Whether the button is the one large call to action of a page, as
    /// `controlSize(.extraLarge)` asks.
    private var isLarge: Bool { controlSize == .extraLarge }

    /// Whether the button sits in a compact space, such as a card in the
    /// sidebar, as `controlSize(.small)` asks.
    private var isCompact: Bool { controlSize == .small || controlSize == .mini }

    /// The title's type at the button's size.
    private var titleFont: Font {
        if isLarge { return CrestTypography.largeButtonTitle }
        return isCompact ? CrestTypography.compactButtonTitle : CrestTypography.buttonTitle
    }

    // MARK: - Actions - Sizing

    /// The height of a primary or secondary button at its size.
    private var height: CGFloat {
        if isLarge { return CrestButtonMetrics.largeHeight }
        if isCompact { return CrestButtonMetrics.compactHeight }
        return CrestButtonMetrics.height
    }

    /// The room either side of a primary button's title at its size, and of
    /// a secondary one's.
    private func horizontalPadding(isProminent: Bool) -> CGFloat {
        if isLarge { return CrestButtonMetrics.largeHorizontalPadding }
        if isCompact { return CrestButtonMetrics.compactHorizontalPadding }
        return isProminent
            ? CrestButtonMetrics.prominentHorizontalPadding : CrestButtonMetrics.standardHorizontalPadding
    }

    // MARK: - Actions - Drawing

    var body: some View {
        rendered
            .crestPressFeedback(
                isPressed: configuration.isPressed,
                isEnabled: isEnabled
            )
            .onHover { isHovering = $0 && isEnabled }
    }

    @ViewBuilder
    private var rendered: some View {
        switch role {
        case .primary:
            primary
        case .secondary:
            secondary
        case .tertiary:
            tertiary
        case .destructive:
            destructive
        case .icon(let diameter, let isProminent):
            icon(diameter: diameter, isProminent: isProminent)
        }
    }

    /// The one action that leads on: a solid pill in Crest blue, the color of
    /// what a person can press, under a faint sheen along its top, or in a
    /// caller's tint, with white or black text as reads best.
    private var primary: some View {
        let fill = tint ?? CrestBrandTheme.action
        return configuration.label
            .font(titleFont)
            .foregroundStyle(fill.perceptualForeground(in: colorScheme))
            .padding(.horizontal, horizontalPadding(isProminent: true))
            .frame(minHeight: height)
            .background {
                Capsule().fill(fill.opacity(primaryFillOpacity))
            }
            .overlay {
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(CrestButtonMetrics.sheenOpacity), .white.opacity(0)],
                        startPoint: .top, endPoint: .center),
                    lineWidth: CrestButtonMetrics.strokeWidth
                )
            }
            .crestElevation(.control)
            .crestCapsuleInteractionShape()
    }

    /// A real alternative: a quiet pill of the text's own color, clear
    /// enough to show the surface under it.
    private var secondary: some View {
        configuration.label
            .font(titleFont)
            .foregroundStyle(.primary)
            .padding(.horizontal, horizontalPadding(isProminent: false))
            .frame(minHeight: height)
            .background {
                Capsule().fill(Color.primary.opacity(secondaryFillOpacity))
            }
            .overlay {
                Capsule().strokeBorder(
                    Color.primary.opacity(CrestButtonMetrics.quietStrokeOpacity),
                    lineWidth: CrestButtonMetrics.strokeWidth
                )
            }
            .crestCapsuleInteractionShape()
    }

    private var primaryFillOpacity: Double {
        if configuration.isPressed { return CrestButtonMetrics.pressedFillOpacity }
        return isHovering ? 1 : CrestButtonMetrics.primaryRestFill
    }

    private var secondaryFillOpacity: Double {
        if configuration.isPressed { return CrestButtonMetrics.quietPressedFill }
        return isHovering ? CrestButtonMetrics.quietHoverFill : CrestButtonMetrics.quietRestFill
    }

    private var destructive: some View {
        let tint = resolvedTint
        return configuration.label
            .font(
                CrestTypography.sans(
                    CrestButtonMetrics.standardLabelSize,
                    weight: .semibold
                )
            )
            .foregroundStyle(resolvedTextTint)
            .padding(.horizontal, CrestButtonMetrics.standardHorizontalPadding)
            .frame(minHeight: CrestButtonMetrics.height)
            .background {
                Capsule().fill(tint.opacity(tintedFillOpacity(isEmphasized: false)))
            }
            .overlay {
                Capsule().strokeBorder(
                    tint.opacity(CrestButtonMetrics.tintEmphasizedStroke),
                    lineWidth: CrestButtonMetrics.strokeWidth
                )
            }
            .crestCapsuleInteractionShape()
    }

    private var tertiary: some View {
        configuration.label
            .font(CrestTypography.controlTitle)
            .foregroundStyle(resolvedTextTint)
            .padding(.horizontal, CrestButtonMetrics.quietHorizontalPadding)
            .frame(minHeight: CrestLayout.minimumHitTarget)
            .crestInteractiveSurface(
                isSelected: false,
                isHovering: isHovering,
                cornerRadius: CrestRadius.compact,
                isPressed: configuration.isPressed
            )
            .contentShape(.rect(cornerRadius: CrestRadius.compact, style: .continuous))
            .crestFocusShape(
                RoundedRectangle(cornerRadius: CrestRadius.compact, style: .continuous)
            )
    }

    private func icon(diameter: CGFloat, isProminent: Bool) -> some View {
        // A quiet glyph is a neutral action and draws in the secondary text
        // colour; only a prominent one, or one given a tint, takes a colour.
        let tint = tint ?? (isProminent ? CrestBrandTheme.accent : CrestColor.textSecondary)
        let hitTarget = max(diameter, CrestLayout.minimumHitTarget)
        return configuration.label
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background {
                Circle().fill(
                    tint.opacity(tintedFillOpacity(isEmphasized: isProminent))
                )
            }
            .overlay {
                Circle().strokeBorder(
                    tint.opacity(
                        isProminent
                            ? CrestButtonMetrics.tintEmphasizedStroke
                            : CrestButtonMetrics.tintRestStroke
                    ),
                    lineWidth: isProminent
                        ? CrestButtonMetrics.prominentStrokeWidth
                        : CrestButtonMetrics.quietStrokeWidth
                )
            }
            .frame(width: hitTarget, height: hitTarget)
            .contentShape(.rect)
            .crestFocusShape(Circle())
    }

    private var resolvedTint: Color { tint ?? CrestBrandTheme.accent }
    private var resolvedTextTint: Color { tint ?? CrestBrandTheme.accentText }

    private func tintedFillOpacity(isEmphasized: Bool) -> Double {
        switch (configuration.isPressed, isEmphasized || isHovering) {
        case (true, _):
            CrestButtonMetrics.tintPressedFill
        case (false, true):
            CrestButtonMetrics.tintEmphasizedFill
        case (false, false):
            CrestButtonMetrics.tintRestFill
        }
    }
}

#if DEBUG
    #Preview("Button roles") {
        VStack(spacing: 16) {
            Button("Save Setup") {}.buttonStyle(.crestPrimary)
            Button("Back") {}.buttonStyle(.crestSecondary)
            Button("Delete") {}.buttonStyle(.crestDestructive)
            Button("Manage Filter Lists") {}.buttonStyle(.crestTertiary)
            Button("Disabled") {}.buttonStyle(.crestPrimary).disabled(true)
            Button("Install") {}.buttonStyle(.crestPrimary).controlSize(.small)
        }.padding().frame(width: 300)
    }
#endif
