import CoreGraphics
import SwiftUI

/// The square of grain ``CrestFilmGrain`` repeats: every pixel a little light
/// or dark from a fixed seed, most of them close to clear and few strong,
/// drawn once for each screen scale and kept. Each pixel stands alone, so the
/// tiles meet without a seam.
@MainActor
enum CrestFilmGrainTile {
    // MARK: - Static Variables

    /// The side of the tile, in points.
    static let side: CGFloat = 256
    /// The strongest a pixel's grain gets, out of 255.
    private static let strength = 62.0
    private static var tiles: [CGFloat: CGImage] = [:]

    // MARK: - Actions - Drawing

    /// The tile for a screen of `scale`, drawn the first time it is asked for.
    static func image(scale: CGFloat) -> CGImage? {
        let scale = max(1, scale)
        if let tile = tiles[scale] { return tile }
        let tile = draw(scale: scale)
        tiles[scale] = tile
        return tile
    }

    private static func draw(scale: CGFloat) -> CGImage? {
        let pixels = Int((side * scale).rounded())
        var generator = CrestGrainGenerator(seed: 0xC2E5_7A11)
        var rgba = [UInt8](repeating: 0, count: pixels * pixels * 4)
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            // The difference of two even draws leans toward zero, so most
            // pixels stay near clear and strong grains are rare.
            let noise = generator.nextUnit() - generator.nextUnit()
            let alpha = UInt8((abs(noise) * strength).rounded())
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
}
