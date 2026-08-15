import SwiftUI

extension BrowserSpaceCrestOrdinary {
    var barRendering:
        (
            widthFactor: CGFloat?,
            heightFactor: CGFloat?,
            rotationDegrees: Double
        )?
    {
        switch self {
        case .pale:
            (0.18, nil, 0)
        case .fess:
            (nil, 0.17, 0)
        case .bend:
            (1.1, 0.17, -38)
        default:
            nil
        }
    }

    var symbolRendering:
        (
            systemImage: String,
            sizeFactor: CGFloat,
            verticalOffsetFactor: CGFloat
        )?
    {
        switch self {
        case .chevron:
            ("chevron.up", 0.46, 0.07)
        case .cross:
            ("plus", 0.48, 0)
        case .saltire:
            ("xmark", 0.48, 0)
        default:
            nil
        }
    }
}
