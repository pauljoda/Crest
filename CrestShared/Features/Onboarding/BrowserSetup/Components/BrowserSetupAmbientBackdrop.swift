import SwiftUI

/// The room setup's window sits in, lit by the look it shows: a soft glow of
/// the Space's Background, with its Accent caught low in a corner, over a
/// ground dark or light as the look is, under a fine grain. Every choice in
/// setup is felt across the whole window, not only in the preview.
struct BrowserSetupAmbientBackdrop: View {
    // MARK: - Variables

    /// The look the room takes its light from, or nil before there is one.
    let look: SpaceBranding?
    /// Whether the welcome is idling through looks, which change a step at a
    /// time and which the room follows smoothly; a choice the person makes
    /// it eases into quickly.
    var isIdling = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var light: BrowserSetupAmbientLight {
        BrowserSetupAmbientLight(look: look)
    }

    // MARK: - Actions - Drawing

    var body: some View {
        let light = light
        GeometryReader { geometry in
            let reach = max(geometry.size.width, geometry.size.height)
            ZStack {
                light.ground
                glow(light.first, at: UnitPoint(x: 0.72, y: 0.36), reach: reach * 0.55)
                glow(light.accent, at: UnitPoint(x: 0.94, y: 0.92), reach: reach * 0.42)
                glow(light.last, at: UnitPoint(x: 0.36, y: 0.98), reach: reach * 0.48)
                CrestGrain()
                    .blendMode(.softLight)
                    .opacity(BrowserSetupAmbientBackdropMetrics.grain)
            }
        }
        .animation(
            (isIdling ? BrowserSetupAmbientBackdropMetrics.following : CrestMotion.onboardingBackdropChange)
                .unlessReducingMotion(reduceMotion), value: light
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, at center: UnitPoint, reach: CGFloat) -> some View {
        RadialGradient(colors: [color, color.opacity(0)], center: center, startRadius: 0, endRadius: reach)
    }
}

/// The colors the room is lit in, which change together as one value.
private struct BrowserSetupAmbientLight: Equatable {
    let ground: Color
    let first: Color
    let last: Color
    let accent: Color

    init(look: SpaceBranding?) {
        let background = look?.backgroundFill.colors ?? [BrandColor.indigo]
        let isDark = look.map { $0.foregroundTone(over: .dark) == .light } ?? true
        ground = isDark ? BrowserSetupAmbientBackdropMetrics.darkGround : BrowserSetupAmbientBackdropMetrics.lightGround
        first = background[0].color
        last = background[background.count - 1].color
        accent = (look?.accentFill.colors.first ?? .sand).color.opacity(
            BrowserSetupAmbientBackdropMetrics.accentStrength)
    }
}

enum BrowserSetupAmbientBackdropMetrics {
    static let darkGround = Color(white: 0.06)
    static let lightGround = Color(white: 0.93)
    /// How strongly the Accent glows beside the Background.
    static let accentStrength = 0.8
    static let grain = 0.7
    /// How the room follows a look that changes a step at a time, carrying
    /// its motion from one step into the next.
    static let following = Animation.smooth(duration: CrestMotion.onboardingBackdropChangeFade)
}
