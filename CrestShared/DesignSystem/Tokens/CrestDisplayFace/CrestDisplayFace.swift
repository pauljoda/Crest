import CoreText
import SwiftUI

/// The face Crest sets its voice in: Allo, variable in weight, roundness and
/// optical size, drawn at its roundest. It ships inside the app under the SIL
/// Open Font License and is registered for this process the first time a
/// font is made from it. Should it ever be missing, the system's rounded face
/// stands in, at the same weight.
struct CrestDisplayFace: Sendable {
    // MARK: - Types

    /// A weight the face is drawn at: its value on the face's weight axis,
    /// and the system weight that stands in for it.
    struct Weight: Sendable {
        static let bold = Weight(axisValue: 700, system: .bold)
        static let heavy = Weight(axisValue: 800, system: .heavy)

        let axisValue: Double
        let system: Font.Weight
    }

    // MARK: - Static Variables

    static let allo = CrestDisplayFace(
        fileName: "AlloVariable", postScriptName: "AlloVariable-Regular", roundness: 100,
        opticalSizes: 9...32)

    /// The face's variation axes, by their four-letter tags.
    private static let weightAxis = axis("wght")
    private static let roundnessAxis = axis("ROND")
    private static let opticalSizeAxis = axis("opsz")
    private static let registration = CrestDisplayFaceRegistration()

    // MARK: - Variables

    /// The font file in the app's resources, without its extension.
    let fileName: String
    let postScriptName: String
    /// Where on the roundness axis the face is drawn.
    let roundness: Double
    /// The optical sizes the face is drawn for; a size outside them takes
    /// the nearest.
    let opticalSizes: ClosedRange<Double>

    // MARK: - Actions - Fonts

    /// The face at `size` and `weight`, its optical size following the size.
    func font(size: CGFloat, weight: Weight) -> Font {
        guard isRegistered else { return .system(size: size, weight: weight.system, design: .rounded) }
        let variation: [NSNumber: NSNumber] = [
            Self.weightAxis: NSNumber(value: weight.axisValue),
            Self.roundnessAxis: NSNumber(value: roundness),
            Self.opticalSizeAxis: NSNumber(
                value: min(max(Double(size), opticalSizes.lowerBound), opticalSizes.upperBound)),
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(
            [kCTFontNameAttribute: postScriptName, kCTFontVariationAttribute: variation] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }

    // MARK: - Actions - Registration

    /// Whether the face is available to this process, registering it the
    /// first time it is asked.
    private var isRegistered: Bool {
        Self.registration.isRegistered(self)
    }

    // MARK: - Actions - Axes

    /// An axis's identifier, made from its four-letter tag.
    private static func axis(_ tag: String) -> NSNumber {
        NSNumber(value: tag.unicodeScalars.reduce(0) { $0 << 8 | Int($1.value) })
    }
}
