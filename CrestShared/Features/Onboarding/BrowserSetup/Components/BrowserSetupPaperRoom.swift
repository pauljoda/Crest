import SwiftUI

/// The room setup's window sits in: a sheet of paper in the colors of the
/// look it shows, the Space's Background running as its sidebar's does,
/// softened toward parchment, or slate in the dark, so the window stands
/// forward, under a fine grain. Every choice in setup colors the room as
/// well as the preview.
struct BrowserSetupPaperRoom: View {
    // MARK: - Variables

    /// The look the room takes its colors from, or nil before there is one.
    let look: SpaceBranding?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Actions - Drawing

    var body: some View {
        let ground =
            colorScheme == .dark ? BrowserSetupPaperRoomMetrics.darkGround : BrowserSetupPaperRoomMetrics.lightGround
        let tones = BrowserSetupPaperRoomTones(look: look ?? SpaceHouse.crest.look, ground: ground)
        ZStack {
            Rectangle()
                .fill(CrestColorFill(tones.colors, degrees: tones.degrees).style)
            CrestGrain(style: .speckled(density: BrowserSetupPaperRoomMetrics.grainDensity))
                .blendMode(.softLight)
                .opacity(BrowserSetupPaperRoomMetrics.grain)
        }
        .animation(CrestMotion.onboardingBackdropChange.unlessReducingMotion(reduceMotion), value: tones)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The colors the room wears, which change together as one value: the
/// look's Background colors, each softened toward the ground, running the
/// way the Background does.
private struct BrowserSetupPaperRoomTones: Equatable {
    let colors: [BrandColor]
    let degrees: Double

    init(look: SpaceBranding, ground: BrandColor) {
        let background = look.backgroundFill
        colors = background.colors.map {
            CrestPerceptualColor.mix($0, ground, by: BrowserSetupPaperRoomMetrics.softening)
        }
        degrees = background.degrees
    }
}

enum BrowserSetupPaperRoomMetrics {
    /// The paper the look's colors soften toward: parchment in the light,
    /// slate in the dark.
    static let lightGround = BrandColor(red: 0.965, green: 0.933, blue: 0.859)
    static let darkGround = BrandColor(red: 0.169, green: 0.227, blue: 0.361)
    /// How far the look's colors soften toward the ground.
    static let softening = 0.35
    static let grain = 0.45
    /// The room's grain is sparser than a sidebar's, as it always drew it
    /// across a whole window.
    static let grainDensity = 1.0 / 60
}
