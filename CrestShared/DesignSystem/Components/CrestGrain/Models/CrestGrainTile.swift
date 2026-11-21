import CoreGraphics
import SwiftUI

/// Deterministic grain tiles cached by screen scale and style.
@MainActor
enum CrestGrainTile {
    // MARK: - Types

    private struct Key: Hashable {
        let scale: CGFloat
        let style: CrestGrain.Style
    }

    // MARK: - Static Variables

    /// The side of the tile, in points.
    static let side: CGFloat = 512
    private static var tiles: [Key: CGImage] = [:]

    // MARK: - Actions - Drawing

    static func image(scale: CGFloat, style: CrestGrain.Style) -> CGImage? {
        let key = Key(scale: max(1, scale), style: style)
        if let tile = tiles[key] { return tile }
        let tile: CGImage? =
            switch style {
            case .fine: drawFine(scale: key.scale)
            case .speckled(let density): drawSpeckled(scale: key.scale, density: density)
            }
        tiles[key] = tile
        return tile
    }

    private static func drawFine(scale: CGFloat) -> CGImage? {
        let pixels = Int((256 * scale).rounded())
        var generator = CrestGrainGenerator(seed: 0xC2E5_7A11)
        var rgba = [UInt8](repeating: 0, count: pixels * pixels * 4)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            // Most pixels are near neutral; strong light and dark grains are rarer.
            let noise = generator.nextUnit() - generator.nextUnit()
            let alpha = UInt8((abs(noise) * 62).rounded())
            let channel: UInt8 = noise > 0 ? alpha : 0
            rgba[offset] = channel
            rgba[offset + 1] = channel
            rgba[offset + 2] = channel
            rgba[offset + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(
            width: pixels, height: pixels, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func drawSpeckled(scale: CGFloat, density: Double) -> CGImage? {
        let pixels = Int((side * scale).rounded())
        guard
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        var generator = CrestGrainGenerator(seed: 0xC2E5_7A11)
        let light = CGMutablePath()
        let dark = CGMutablePath()
        let count = Int((side * side * density).rounded())
        for index in 0..<count {
            let x = generator.nextUnit() * side
            let y = generator.nextUnit() * side
            let diameter = 0.85 + generator.nextUnit() * 1.5
            let path = index.isMultiple(of: 2) ? light : dark
            for speck in wrapped(CGRect(x: x, y: y, width: diameter, height: diameter)) {
                path.addEllipse(in: speck)
            }
        }
        context.addPath(light)
        context.setFillColor(CGColor(gray: 1, alpha: 0.46))
        context.fillPath()
        context.addPath(dark)
        context.setFillColor(CGColor(gray: 0, alpha: 0.38))
        context.fillPath()
        return context.makeImage()
    }

    /// `speck`, and its copies across the edges it crosses.
    private static func wrapped(_ speck: CGRect) -> [CGRect] {
        let shiftsX: [CGFloat] = speck.maxX > side ? [0, -side] : [0]
        let shiftsY: [CGFloat] = speck.maxY > side ? [0, -side] : [0]
        return shiftsX.flatMap { dx in shiftsY.map { dy in speck.offsetBy(dx: dx, dy: dy) } }
    }
}
