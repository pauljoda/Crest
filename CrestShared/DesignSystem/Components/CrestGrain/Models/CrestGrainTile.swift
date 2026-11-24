import CoreGraphics
import SwiftUI

/// The square of grain ``CrestGrain`` repeats: light and dark specks
/// scattered from a fixed seed, drawn once for each screen scale and density
/// and kept. A speck crossing an edge is drawn again across the opposite
/// edge, so the tiles meet without a seam.
@MainActor
enum CrestGrainTile {
    // MARK: - Types

    private struct Key: Hashable {
        let scale: CGFloat
        let density: Double
    }

    // MARK: - Static Variables

    /// The side of the tile, in points.
    static let side: CGFloat = 512
    private static var tiles: [Key: CGImage] = [:]

    // MARK: - Actions - Drawing

    /// The tile for a screen of `scale` with `density` specks a square
    /// point, drawn the first time it is asked for.
    static func image(scale: CGFloat, density: Double) -> CGImage? {
        let key = Key(scale: max(1, scale), density: density)
        if let tile = tiles[key] { return tile }
        let tile = draw(key)
        tiles[key] = tile
        return tile
    }

    private static func draw(_ key: Key) -> CGImage? {
        let pixels = Int((side * key.scale).rounded())
        guard
            let context = CGContext(
                data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: key.scale, y: key.scale)
        var generator = CrestGrainGenerator(seed: 0xC2E5_7A11)
        let light = CGMutablePath()
        let dark = CGMutablePath()
        let count = Int((side * side * key.density).rounded())
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
