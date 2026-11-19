import SwiftUI

struct CrestButtonSurface: View {
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
            .font(isLarge ? CrestTypography.largeButtonTitle : CrestTypography.buttonTitle)
            .foregroundStyle(fill.perceptualForeground(in: colorScheme))
            .padding(
                .horizontal,
                isLarge ? CrestButtonMetrics.largeHorizontalPadding : CrestButtonMetrics.prominentHorizontalPadding
            )
            .frame(minHeight: isLarge ? CrestButtonMetrics.largeHeight : CrestButtonMetrics.prominentHeight)
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
            .shadow(
                color: .black.opacity(CrestButtonMetrics.primaryShadowOpacity),
                radius: CrestButtonMetrics.primaryShadowRadius, y: 1
            )
            .crestCapsuleInteractionShape()
    }

    /// A real alternative: a quiet pill of the text's own color, clear
    /// enough to show the surface under it.
    private var secondary: some View {
        configuration.label
            .font(isLarge ? CrestTypography.largeButtonTitle : CrestTypography.buttonTitle)
            .foregroundStyle(.primary)
            .padding(
                .horizontal,
                isLarge ? CrestButtonMetrics.largeHorizontalPadding : CrestButtonMetrics.standardHorizontalPadding
            )
            .frame(minHeight: isLarge ? CrestButtonMetrics.largeHeight : CrestButtonMetrics.standardHeight)
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
            .frame(minHeight: CrestButtonMetrics.standardHeight)
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
        }.padding().frame(width: 300)
    }
#endif
