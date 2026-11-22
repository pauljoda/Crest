import Foundation

/// Where Crest puts the colors it adds to a gradient, as people's color
/// preferences and curated gradients measure pleasing ones, worked in OKLCH
/// so a hue turn keeps the lightness the eye sees.
///
/// - **Hue:** each added color turns 45° on from the last, so three span 90°,
///   the way most well-liked gradients run between neighboring hues rather
///   than across the wheel. The turn goes whichever way keeps its colors
///   vivid and clear of mud (dark oranges, yellows and olives).
/// - **Lightness:** each added color steps lighter from a dark or middling
///   color and darker from a near-white one, leaning toward where its own hue
///   is most vivid, and never so far that the text over the gradient, white
///   over dark and black over light, reads under 4.5:1.
/// - **Chroma:** vivid enough to show (more on light gradients than dark),
///   within what sRGB holds; a muted color keeps muted partners, and a gray
///   keeps gray ones, with no hue made up.
///
/// The research, with its sources and test colors, is Crest's color harmony
/// note; the numbers here are its tuned values.
struct CrestColorHarmony {
    // MARK: - Variables

    /// Whether the colors have no hue to speak of.
    private let isAchromatic: Bool
    /// Whether the colors are a muted family, a tinted neutral such as cream
    /// or slate.
    private let isTinted: Bool
    /// Whether white text reads better than black over the colors, which the
    /// added ones keep.
    private let isDark: Bool
    /// The contrast every added color keeps with the text: 4.5:1, or the
    /// color it follows's own when that is lower.
    private let textFloor: Double

    // MARK: - Initializers

    private init(reading color: CrestPerceptualColor, isAchromatic: Bool, isTinted: Bool) {
        self.isAchromatic = isAchromatic
        self.isTinted = isTinted
        let luminance = CrestPerceptualColor.luminance(of: color.color)
        let onWhite = CrestPerceptualColor.contrast(1, luminance)
        let onBlack = CrestPerceptualColor.contrast(0, luminance)
        isDark = onWhite >= onBlack
        textFloor = min(CrestColorHarmonyMetrics.textContrast, isDark ? onWhite : onBlack)
    }

    // MARK: - Functions

    /// The second and third colors Crest adds beside `base`, in order: the
    /// second is the one a person gets first, and the third follows it when
    /// they add another without moving the second.
    static func run(beside base: BrandColor) -> [BrandColor] {
        let color = CrestPerceptualColor(base)
        let isAchromatic = color.chroma < CrestColorHarmonyMetrics.achromaticChroma
        let harmony = CrestColorHarmony(
            reading: color, isAchromatic: isAchromatic,
            isTinted: !isAchromatic && color.chroma < CrestColorHarmonyMetrics.tintedChroma)
        let direction: Double = harmony.isDark || color.lightness < CrestColorHarmonyMetrics.nearWhite ? 1 : -1
        let metrics = CrestColorHarmonyMetrics.self
        if isAchromatic {
            let second = harmony.place(
                from: color.lightness, reference: 0, degrees: color.degrees, direction: direction,
                step: metrics.secondStep, mayFlip: true)
            let third = harmony.place(
                from: second.lightness, reference: 0, degrees: color.degrees, direction: second.direction,
                step: metrics.thirdStep, mayFlip: false)
            return [second.color, third.color]
        }
        let candidates = [1.0, -1.0].map { turn in
            let second = harmony.place(
                from: color.lightness, reference: color.chroma, degrees: color.degrees + turn * metrics.hueStep,
                direction: direction, step: metrics.secondStep, mayFlip: true)
            let reference = harmony.isTinted ? color.chroma : max(color.chroma, second.chroma)
            let third = harmony.place(
                from: second.lightness, reference: reference, degrees: color.degrees + 2 * turn * metrics.hueStep,
                direction: second.direction, step: metrics.thirdStep, mayFlip: false)
            let score =
                second.chroma / harmony.wantedChroma(second.lightness, reference: color.chroma)
                + 0.5 * third.chroma / harmony.wantedChroma(third.lightness, reference: reference)
                - (second.perceptual.isMuddy ? 1 : 0) - (third.perceptual.isMuddy ? 1 : 0)
            return (turn: turn, score: score, colors: [second.color, third.color])
        }
        let (increasing, decreasing) = (candidates[0], candidates[1])
        let tied = abs(increasing.score - decreasing.score) < metrics.tie
        return tied || increasing.score >= decreasing.score ? increasing.colors : decreasing.colors
    }

    /// The color Crest adds after a person placed `first` and `second`: their
    /// turn of the wheel carried on, a little less far when their colors
    /// contrast, and their step of lightness carried on too.
    static func third(after first: BrandColor, _ second: BrandColor) -> BrandColor {
        let a = CrestPerceptualColor(first)
        let b = CrestPerceptualColor(second)
        let metrics = CrestColorHarmonyMetrics.self
        let firstIsGray = a.chroma < metrics.achromaticChroma
        let secondIsGray = b.chroma < metrics.achromaticChroma
        if firstIsGray, secondIsGray {
            let step = b.lightness - a.lightness
            let isDark = CrestColorHarmony(reading: b, isAchromatic: true, isTinted: false).isDark
            let lightness =
                abs(step) > metrics.flatStep
                ? b.lightness + step / 2 : b.lightness + (isDark ? 1 : -1) * metrics.thirdStep
            return CrestPerceptualColor(
                lightness: min(max(lightness, metrics.darkestGray), metrics.lightestGray), chroma: 0, hue: b.hue
            ).color
        }
        if secondIsGray {
            return run(beside: first)[0]
        }
        let harmony = CrestColorHarmony(reading: b, isAchromatic: false, isTinted: b.chroma < metrics.tintedChroma)
        let turn = firstIsGray ? metrics.hueStep : Self.shorterTurn(from: a.degrees, to: b.degrees)
        let sign: Double = turn >= 0 ? 1 : -1
        let width = abs(turn) <= metrics.contrastingTurn ? min(max(abs(turn), 30), metrics.hueStep) : 30
        let lightnessStep = min(max(abs(b.lightness - a.lightness) / 2, 0.04), 0.10)
        var first: Placed?
        for way in [sign, -sign] {
            let placed = harmony.place(
                from: b.lightness, reference: (a.chroma + b.chroma) / 2, degrees: b.degrees + way * width,
                direction: b.lightness >= a.lightness ? 1 : -1, step: lightnessStep, mayFlip: false)
            if !placed.perceptual.isMuddy { return placed.color }
            first = first ?? placed
        }
        return first?.color ?? second
    }

    /// The shade of `color` that stands just off it: its hue and chroma a
    /// step lighter, or a step darker from a near-white color. A Space's
    /// Pattern takes it from the Space's Background, so a crest's field
    /// reads against the sidebar it sits on.
    static func shade(of color: BrandColor) -> BrandColor {
        let base = CrestPerceptualColor(color)
        let metrics = CrestColorHarmonyMetrics.self
        let step = base.lightness < metrics.nearWhite ? metrics.shadeStep : -metrics.shadeStep
        return CrestPerceptualColor(lightness: base.lightness + step, chroma: base.chroma, hue: base.hue).color
    }

    // MARK: - Actions - Placing

    /// A color Crest placed, with the way its lightness went.
    private struct Placed {
        let lightness: Double
        let chroma: Double
        let degrees: Double
        let direction: Double

        var perceptual: CrestPerceptualColor {
            CrestPerceptualColor(lightness: lightness, chroma: chroma, hue: degrees / 360)
        }

        var color: BrandColor { perceptual.color }
    }

    /// The color at `degrees` a `step` of lightness on from `lightness` in
    /// `direction`, leaning toward where its hue is most vivid. One that can
    /// barely move that way, as a middling color at the edge of white text
    /// can't grow lighter, goes the other way when `mayFlip`.
    private func place(
        from lightness: Double, reference: Double, degrees: Double, direction: Double, step: Double, mayFlip: Bool
    ) -> Placed {
        let metrics = CrestColorHarmonyMetrics.self
        let target = lightness + direction * step
        var pull =
            isAchromatic
            ? 0
            : metrics.cuspPull * (CrestPerceptualColor.cuspLightness(degrees: degrees) - target) * (isTinted ? 0.5 : 1)
        if pull * direction < 0 { pull = direction * max(pull * direction, -step / 2) }
        let placed = settle(target + pull, from: lightness, reference: reference, degrees: degrees)
        if mayFlip, (placed.lightness - lightness) * direction < metrics.leastStep {
            let flipped = settle(lightness - direction * step, from: lightness, reference: reference, degrees: degrees)
            return Placed(lightness: flipped.lightness, chroma: flipped.chroma, degrees: degrees, direction: -direction)
        }
        return Placed(lightness: placed.lightness, chroma: placed.chroma, degrees: degrees, direction: direction)
    }

    /// `target` held near `lightness`, lifted clear of mud on a light
    /// gradient, and moved until the text reads over it, with the chroma
    /// that suits it there.
    private func settle(
        _ target: Double, from lightness: Double, reference: Double, degrees: Double
    ) -> (lightness: Double, chroma: Double) {
        let metrics = CrestColorHarmonyMetrics.self
        let lightest = isAchromatic ? metrics.lightestGray : metrics.lightestColor
        var settled = min(
            max(target, max(metrics.darkestGray, lightness - metrics.farthestStep)),
            min(lightest, lightness + metrics.farthestStep))
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        if !isDark, !isAchromatic, CrestPerceptualColorMetrics.mudHues.contains(normalized) {
            settled = max(settled, CrestPerceptualColor.cuspLightness(degrees: degrees) - metrics.mudLift)
        }
        var chroma = self.chroma(settled, degrees: degrees, reference: reference)
        var nudges = 0
        while nudges < metrics.textSteps, !readsText(settled, chroma: chroma, degrees: degrees) {
            settled += isDark ? -metrics.textNudge : metrics.textNudge
            chroma = self.chroma(settled, degrees: degrees, reference: reference)
            nudges += 1
        }
        return (settled, chroma)
    }

    // MARK: - Actions - Measuring

    /// The chroma an added color wants beside colors of `reference` chroma.
    private func wantedChroma(_ lightness: Double, reference: Double) -> Double {
        let metrics = CrestColorHarmonyMetrics.self
        if isTinted { return min(max(reference * 2, metrics.tintedLeast), metrics.tintedMost) }
        let least =
            isDark ? metrics.darkLeast : (lightness >= metrics.pastel ? metrics.pastelLeast : metrics.lightLeast)
        return min(max(reference * 1.1, least), reference + metrics.mostAbove)
    }

    /// The chroma an added color takes: what it wants, within what sRGB
    /// holds at its lightness and hue, with room to spare.
    private func chroma(_ lightness: Double, degrees: Double, reference: Double) -> Double {
        guard !isAchromatic else { return 0 }
        let most = CrestPerceptualColor.maximumChroma(lightness: lightness, hue: degrees / 360)
        return min(wantedChroma(lightness, reference: reference), CrestColorHarmonyMetrics.gamutShare * most)
    }

    /// Whether the text reads over the color well enough.
    private func readsText(_ lightness: Double, chroma: Double, degrees: Double) -> Bool {
        let color = CrestPerceptualColor(lightness: lightness, chroma: chroma, hue: degrees / 360).color
        let contrast = CrestPerceptualColor.contrast(isDark ? 1 : 0, CrestPerceptualColor.luminance(of: color))
        return contrast >= textFloor
    }

    /// The signed shorter turn from one hue to another, in degrees.
    private static func shorterTurn(from start: Double, to end: Double) -> Double {
        let turn = (end - start).truncatingRemainder(dividingBy: 360)
        return turn > 180 ? turn - 360 : (turn <= -180 ? turn + 360 : turn)
    }
}

enum CrestColorHarmonyMetrics {
    /// How far a shade steps from the color it stands off.
    static let shadeStep = 0.10
    /// Below this chroma a color has no hue to speak of.
    static let achromaticChroma = 0.012
    /// Below this chroma a color is a tinted neutral.
    static let tintedChroma = 0.04
    /// How far each added color turns from the last, in degrees.
    static let hueStep = 45.0
    /// The lightness step to the second color, and on to the third.
    static let secondStep = 0.12
    static let thirdStep = 0.08
    /// The least lightness a second color must move to keep its way.
    static let leastStep = 0.06
    /// The most an added color's lightness strays from the color it follows.
    static let farthestStep = 0.18
    /// The share of the way to its hue's vivid lightness an added color leans.
    static let cuspPull = 0.25
    /// The share of what sRGB holds that an added color's chroma may use.
    static let gamutShare = 0.90
    /// A base this light or lighter takes darker partners.
    static let nearWhite = 0.86
    /// The lightest a hued and a gray added color may be, and the darkest.
    static let lightestColor = 0.92
    static let lightestGray = 0.95
    static let darkestGray = 0.18
    /// How far below its vivid lightness a warm color on a light gradient may
    /// sit before it is lifted.
    static let mudLift = 0.15
    /// The contrast the text keeps over every added color.
    static let textContrast = 4.5
    /// How far each nudge for the text moves an added color, and how many.
    static let textNudge = 0.005
    static let textSteps = 80
    /// The chroma floors: on a dark gradient, a light one, and a pastel one.
    static let darkLeast = 0.07
    static let lightLeast = 0.09
    static let pastelLeast = 0.05
    /// The lightness from which a light gradient is pastel.
    static let pastel = 0.85
    /// How far past the colors it follows an added color's chroma may go.
    static let mostAbove = 0.10
    /// A muted family's chroma range.
    static let tintedLeast = 0.03
    static let tintedMost = 0.06
    /// Scores this close are a tie, which turns the hue upward.
    static let tie = 0.05
    /// Two placed colors farther apart than this contrast, and the third
    /// turns only 30°.
    static let contrastingTurn = 120.0
    /// Two grays this close in lightness have no trend to carry on.
    static let flatStep = 0.02
}
