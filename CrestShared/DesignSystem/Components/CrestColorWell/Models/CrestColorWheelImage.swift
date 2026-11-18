import CoreGraphics
import Foundation

/// The color wheel at one lightness as an image, drawn from the rule a
/// handle's color comes from, so the chosen handle always wears the color
/// that lies under it, clear outside its rim. Each step of lightness is
/// drawn once.
@MainActor
enum CrestColorWheelImage {
    // MARK: - Static Variables

    /// How many steps of lightness the wheel is drawn at, from black to
    /// white: fine enough that Brightness moves it smoothly.
    static let steps = 64
    /// The wheel's side in pixels, which the view scales smoothly to any
    /// size it shows it at.
    static let side = 240

    /// The images drawn so far, by step.
    private static var drawn: [Int: CGImage] = [:]

    // MARK: - Functions

    /// The step nearest `lightness`.
    static func step(of lightness: Double) -> Int {
        Int((min(max(lightness, 0), 1) * Double(steps)).rounded())
    }

    /// The wheel at lightness step `step`.
    static func image(step: Int) -> CGImage {
        if let image = drawn[step] { return image }
        let image = draw(lightness: Double(step) / Double(steps))
        drawn[step] = image
        return image
    }

    // MARK: - Actions - Drawing

    private static func draw(lightness: Double) -> CGImage {
        let side = Self.side
        let radius = Double(side) / 2
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for row in 0..<side {
            for column in 0..<side {
                let x = (Double(column) + 0.5 - radius) / radius
                let y = (Double(row) + 0.5 - radius) / radius
                let distance = hypot(x, y)
                // A pixel's worth of soft edge keeps the rim smooth.
                let coverage = min(max((1 - distance) * radius + 0.5, 0), 1)
                guard coverage > 0 else { continue }
                let color = CrestColorWheelPoint(position: CGPoint(x: x, y: y), lightness: lightness).color
                let offset = (row * side + column) * 4
                bytes[offset] = channel(color.red * coverage)
                bytes[offset + 1] = channel(color.green * coverage)
                bytes[offset + 2] = channel(color.blue * coverage)
                bytes[offset + 3] = channel(coverage)
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { preconditionFailure("The color wheel's image could not be drawn.") }
        return image
    }

    private static func channel(_ value: Double) -> UInt8 {
        UInt8(clamping: Int((min(max(value, 0), 1) * 255).rounded()))
    }
}
