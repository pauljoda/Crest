import SwiftUI

/// The house colors of Crest's identity, shared by its public brand and its
/// first-party app surfaces: cream, paper and ink for grounds and text, Crest
/// blue for anything a person can press or select, and butter, coral and sky,
/// the three paper banners of the mark, kept for the mark, crests, gradients
/// and marketing, never for actions. Space colors remain user-owned and more
/// expressive.
enum CrestBrandPalette {
    static let inkComponents = CrestColorComponents(red: 23, green: 34, blue: 56)
    static let slateComponents = CrestColorComponents(red: 43, green: 58, blue: 92)
    static let creamComponents = CrestColorComponents(red: 251, green: 245, blue: 230)
    static let paperComponents = CrestColorComponents(red: 255, green: 253, blue: 247)
    /// The warm ground under a control on cream, such as a segmented
    /// picker's track.
    static let parchmentComponents = CrestColorComponents(red: 246, green: 238, blue: 219)
    /// The warm hairline round a card on cream.
    static let hairlineComponents = CrestColorComponents(red: 234, green: 223, blue: 198)
    static let crestBlueComponents = CrestColorComponents(red: 43, green: 108, blue: 196)
    static let butterComponents = CrestColorComponents(red: 242, green: 193, blue: 78)
    static let coralComponents = CrestColorComponents(red: 233, green: 96, blue: 75)
    static let skyComponents = CrestColorComponents(red: 98, green: 169, blue: 216)
    static let sageComponents = CrestColorComponents(red: 141, green: 191, blue: 154)
    /// The gold of small caps labels on cream.
    static let goldComponents = CrestColorComponents(red: 138, green: 106, blue: 34)

    static let ink = inkComponents.color
    static let slate = slateComponents.color
    static let cream = creamComponents.color
    static let paper = paperComponents.color
    static let parchment = parchmentComponents.color
    static let hairline = hairlineComponents.color
    static let crestBlue = crestBlueComponents.color
    static let butter = butterComponents.color
    static let coral = coralComponents.color
    static let sky = skyComponents.color
    static let sage = sageComponents.color
    static let gold = goldComponents.color
    static let match = sage
    static let line = ink.opacity(CrestOpacity.brandHairline)
}
