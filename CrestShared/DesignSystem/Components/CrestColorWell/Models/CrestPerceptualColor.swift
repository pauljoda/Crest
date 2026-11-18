import Foundation

/// A color as the eye measures it, in OKLCH: its perceived lightness from 0
/// for black to 1 for white, its chroma, how far it stands from gray, and its
/// hue as a turn of the wheel from 0 up to 1. Turning the hue keeps the
/// lightness the eye sees, which turning an HSL hue does not: an HSL yellow
/// and blue of one lightness look far apart. Converting back keeps the
/// lightness and hue and gives up chroma until the color fits sRGB.
/// The conversions are Björn Ottosson's, https://bottosson.github.io/posts/oklab/.
struct CrestPerceptualColor: Equatable, Sendable {
    // MARK: - Static Variables

    /// The lightness at which sRGB holds the most chroma, every 10° of hue
    /// from 0: where each hue is most vivid, light for yellow and dark for
    /// blue-violet. Ottosson's sRGB cusp.
    private static let cuspLightnesses: [Double] = [
        0.647, 0.639, 0.632, 0.632, 0.681, 0.721, 0.756, 0.790, 0.825, 0.863, 0.909, 0.967,
        0.939, 0.910, 0.876, 0.874, 0.882, 0.889, 0.896, 0.902, 0.882, 0.841, 0.802, 0.762,
        0.717, 0.661, 0.574, 0.465, 0.489, 0.518, 0.552, 0.595, 0.648, 0.697, 0.675, 0.659,
    ]

    // MARK: - Variables

    let lightness: Double
    let chroma: Double
    /// The hue, from 0 up to 1.
    let hue: Double

    /// The color in sRGB: this lightness and hue at the most chroma up to
    /// its own that sRGB holds.
    var color: BrandColor {
        if let fitting = Self.rgb(lightness, chroma, hue) { return fitting }
        var low = 0.0
        var high = chroma
        for _ in 0..<CrestPerceptualColorMetrics.gamutSteps {
            let middle = (low + high) / 2
            if Self.rgb(lightness, middle, hue) == nil { high = middle } else { low = middle }
        }
        return Self.rgb(lightness, low, hue) ?? Self.clamped(lightness, low, hue)
    }

    /// The hue in degrees, from 0 up to 360.
    var degrees: Double { hue * 360 }

    /// Whether the color reads as mud: an orange, yellow or olive well darker
    /// than the lightness where its hue is vivid. Dark yellows and oranges,
    /// olive and brown, are the colors people like least.
    var isMuddy: Bool {
        chroma >= CrestPerceptualColorMetrics.mudChroma
            && CrestPerceptualColorMetrics.mudHues.contains(degrees)
            && lightness < Self.cuspLightness(degrees: degrees) - CrestPerceptualColorMetrics.mudDepth
    }

    // MARK: - Initializers

    init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = min(max(lightness, 0), 1)
        self.chroma = max(chroma, 0)
        let turned = hue.truncatingRemainder(dividingBy: 1)
        self.hue = turned < 0 ? turned + 1 : turned
    }

    init(_ color: BrandColor) {
        let (l, a, b) = Self.oklab(red: color.red, green: color.green, blue: color.blue)
        self.init(lightness: l, chroma: hypot(a, b), hue: atan2(b, a) / (2 * .pi))
    }

    // MARK: - Actions - Measuring

    /// The most chroma sRGB holds at `lightness` and `hue`, a turn from 0
    /// up to 1.
    static func maximumChroma(lightness: Double, hue: Double) -> Double {
        var low = 0.0
        var high = CrestPerceptualColorMetrics.chromaCeiling
        for _ in 0..<CrestPerceptualColorMetrics.gamutSteps {
            let middle = (low + high) / 2
            if rgb(lightness, middle, hue) == nil { high = middle } else { low = middle }
        }
        return low
    }

    /// The lightness where `degrees` of hue is most vivid in sRGB, between
    /// the table's tens.
    static func cuspLightness(degrees: Double) -> Double {
        let turned = degrees.truncatingRemainder(dividingBy: 360)
        let position = (turned < 0 ? turned + 360 : turned) / 10
        let below = Int(position) % cuspLightnesses.count
        let above = (below + 1) % cuspLightnesses.count
        let fraction = position - position.rounded(.down)
        return cuspLightnesses[below] + (cuspLightnesses[above] - cuspLightnesses[below]) * fraction
    }

    /// How luminous `color` is, as WCAG contrast measures it.
    static func luminance(of color: BrandColor) -> Double {
        0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
    }

    /// The WCAG contrast between two luminances.
    static func contrast(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    // MARK: - Actions - Blending

    /// The stops a gradient of `colors` draws, evenly spaced, with stops
    /// between any two neighbors whose hues stand far apart: a straight blend
    /// of far hues passes through gray, so those neighbors turn around the
    /// wheel in small steps instead, the short way unless that way crosses
    /// mud and the long way doesn't.
    static func blendingStops(_ colors: [BrandColor]) -> [(color: BrandColor, location: Double)] {
        guard colors.count > 1 else { return colors.map { ($0, 0) } }
        let metrics = CrestPerceptualColorMetrics.self
        let span = 1 / Double(colors.count - 1)
        var stops = [(color: colors[0], location: 0.0)]
        for (index, pair) in zip(colors, colors.dropFirst()).enumerated() {
            let (a, b) = (CrestPerceptualColor(pair.0), CrestPerceptualColor(pair.1))
            var turn = shorterTurn(from: a.degrees, to: b.degrees)
            if a.chroma >= metrics.blendChroma, b.chroma >= metrics.blendChroma, abs(turn) > metrics.blendTurn {
                let other = turn > 0 ? turn - 360 : turn + 360
                if crossesMud(a, b, turn: turn), !crossesMud(a, b, turn: other) { turn = other }
                let steps = Int((abs(turn) / metrics.blendStep).rounded(.up))
                for step in 1..<steps {
                    let fraction = Double(step) / Double(steps)
                    let lightness = a.lightness + (b.lightness - a.lightness) * fraction
                    let hue = (a.degrees + turn * fraction) / 360
                    let chroma = min(
                        a.chroma + (b.chroma - a.chroma) * fraction,
                        maximumChroma(lightness: lightness, hue: hue))
                    let between = CrestPerceptualColor(lightness: lightness, chroma: chroma, hue: hue).color
                    stops.append((between, (Double(index) + fraction) * span))
                }
            }
            stops.append((pair.1, Double(index + 1) * span))
        }
        return stops
    }

    /// Whether turning from `a` to `b` by `turn` degrees passes through mud.
    private static func crossesMud(_ a: CrestPerceptualColor, _ b: CrestPerceptualColor, turn: Double) -> Bool {
        let samples = CrestPerceptualColorMetrics.mudSamples
        return (1..<samples).contains { sample in
            let fraction = Double(sample) / Double(samples)
            return CrestPerceptualColor(
                lightness: a.lightness + (b.lightness - a.lightness) * fraction,
                chroma: a.chroma + (b.chroma - a.chroma) * fraction,
                hue: (a.degrees + turn * fraction) / 360
            ).isMuddy
        }
    }

    /// The signed shorter turn from one hue to another, in degrees.
    private static func shorterTurn(from start: Double, to end: Double) -> Double {
        let turn = (end - start).truncatingRemainder(dividingBy: 360)
        return turn > 180 ? turn - 360 : (turn <= -180 ? turn + 360 : turn)
    }

    // MARK: - Actions - Mixing

    /// The color `amount` of the way from `start` to `end`, mixed in OKLab,
    /// so the colors between change evenly to the eye.
    static func mix(_ start: BrandColor, _ end: BrandColor, by amount: Double) -> BrandColor {
        let (startL, startA, startB) = oklab(red: start.red, green: start.green, blue: start.blue)
        let (endL, endA, endB) = oklab(red: end.red, green: end.green, blue: end.blue)
        let lightness = startL + (endL - startL) * amount
        let a = startA + (endA - startA) * amount
        let b = startB + (endB - startB) * amount
        return clamped(lightness, hypot(a, b), atan2(b, a) / (2 * .pi))
    }

    // MARK: - Actions - Converting

    /// The OKLab coordinates of an sRGB color.
    private static func oklab(red: Double, green: Double, blue: Double) -> (Double, Double, Double) {
        let r = linear(red)
        let g = linear(green)
        let b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    /// The linear sRGB channels of an OKLCH color, which may fall outside
    /// 0 through 1.
    private static func linearRGB(_ lightness: Double, _ chroma: Double, _ hue: Double) -> (Double, Double, Double) {
        let angle = hue * 2 * .pi
        let a = chroma * cos(angle)
        let b = chroma * sin(angle)
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    /// The sRGB color of an OKLCH color, or nil when sRGB cannot hold it.
    private static func rgb(_ lightness: Double, _ chroma: Double, _ hue: Double) -> BrandColor? {
        let (r, g, b) = linearRGB(lightness, chroma, hue)
        let range = -CrestPerceptualColorMetrics.gamutTolerance...(1 + CrestPerceptualColorMetrics.gamutTolerance)
        guard range.contains(r), range.contains(g), range.contains(b) else { return nil }
        return clamped(lightness, chroma, hue)
    }

    /// The sRGB color of an OKLCH color, each channel held within 0 through 1.
    private static func clamped(_ lightness: Double, _ chroma: Double, _ hue: Double) -> BrandColor {
        let (r, g, b) = linearRGB(lightness, chroma, hue)
        return BrandColor(red: encoded(r), green: encoded(g), blue: encoded(b))
    }

    private static func linear(_ channel: Double) -> Double {
        channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ channel: Double) -> Double {
        let held = min(max(channel, 0), 1)
        return held <= 0.0031308 ? 12.92 * held : 1.055 * pow(held, 1 / 2.4) - 0.055
    }
}

enum CrestPerceptualColorMetrics {
    /// How many halvings find the most chroma sRGB holds at a lightness and
    /// hue, which settles it to well under a thousandth.
    static let gamutSteps = 18
    /// More chroma than any sRGB color has.
    static let chromaCeiling = 0.4
    /// The hues that turn to mud when dark: orange, yellow and olive.
    static let mudHues: ClosedRange<Double> = 50...125
    /// How far below its hue's vivid lightness a warm color turns to mud.
    static let mudDepth = 0.20
    /// The least chroma a color needs to read as mud rather than gray.
    static let mudChroma = 0.03
    /// Neighbors in a gradient this vivid or more, and more than this many
    /// degrees apart, blend around the wheel in steps of at most this many.
    static let blendChroma = 0.04
    static let blendTurn = 60.0
    static let blendStep = 30.0
    /// How many points along a turn are checked for mud.
    static let mudSamples = 12
    /// How far past 0 or 1 a linear channel may stray and still count as in
    /// sRGB, for rounding.
    static let gamutTolerance = 0.0001
}
