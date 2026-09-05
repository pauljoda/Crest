import AppKit
import Foundation

/// Captures the inspected page through WebKit, without resizing its WKWebView
/// or moving the user's scroll position.
@MainActor
final class BrowserChromeDebuggerScreenshot {
    private let connection: BrowserWebInspectorProtocolConnection

    init(connection: BrowserWebInspectorProtocolConnection) {
        self.connection = connection
    }

    func capture(parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        let options = try Options(parameters)
        let rectangle = try await rectangle(for: options)
        try Task.checkCancellation()
        let response = try await connection.sendCommand("Page.snapshotRect", parameters: rectangle)
        let prefix = "data:image/png;base64,"
        guard let dataURL = response["dataURL"] as? String, dataURL.hasPrefix(prefix),
            let png = Data(base64Encoded: String(dataURL.dropFirst(prefix.count)))
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        if options.format == "png", options.scale == 1 { return ["data": png.base64EncodedString()] }
        guard let bitmap = NSBitmapImageRep(data: png) else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        let scaled = try scaledBitmap(bitmap, scale: options.scale)
        guard
            let encoded = scaled.representation(
                using: options.format == "png" ? .png : .jpeg,
                properties: options.format == "png" ? [:] : [.compressionFactor: Double(options.quality) / 100])
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        return ["data": encoded.base64EncodedString()]
    }

    private func scaledBitmap(_ bitmap: NSBitmapImageRep, scale: Double) throws -> NSBitmapImageRep {
        guard scale != 1 else { return bitmap }
        guard let width = Int(exactly: max(1, (Double(bitmap.pixelsWide) * scale).rounded())),
            let height = Int(exactly: max(1, (Double(bitmap.pixelsHigh) * scale).rounded())),
            width <= 32768, height <= 32768, width * height <= 128_000_000
        else { throw BrowserChromeDebuggerProtocolError.unsupportedParameter("clip.scale output size") }
        guard let source = bitmap.cgImage,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        return NSBitmapImageRep(cgImage: image)
    }

    private func rectangle(for options: Options) async throws -> [String: Any] {
        if let rectangle = options.rectangle { return rectangle }
        return try await measuredRectangle(fullPage: options.beyondViewport)
    }

    private func measuredRectangle(fullPage: Bool) async throws -> [String: Any] {
        let expression =
            fullPage
            ? "({width: Math.max(innerWidth, document.documentElement.scrollWidth, document.body?.scrollWidth ?? 0), height: Math.max(innerHeight, document.documentElement.scrollHeight, document.body?.scrollHeight ?? 0)})"
            : "({width: innerWidth, height: innerHeight})"
        let measured = try await connection.sendCommand(
            "Runtime.evaluate",
            parameters: [
                "expression": expression, "returnByValue": true, "doNotPauseOnExceptionsAndMuteConsole": true,
            ])
        guard measured["wasThrown"] as? Bool != true,
            let value = (measured["result"] as? [String: Any])?["value"] as? [String: Any]
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        let width = try Options.integer(value["width"], name: "width")
        let height = try Options.integer(value["height"], name: "height")
        guard width > 0, height > 0 else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        return ["x": 0, "y": 0, "width": width, "height": height, "coordinateSystem": fullPage ? "Page" : "Viewport"]
    }

    private struct Options {
        let format: String
        let quality: Int
        let beyondViewport: Bool
        let scale: Double
        let rectangle: [String: Any]?

        init(_ parameters: [String: Any]) throws {
            let known = ["format", "quality", "clip", "fromSurface", "captureBeyondViewport", "optimizeForSpeed"]
            for key in parameters.keys where !known.contains(key) {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter(key)
            }
            guard let format = parameters["format"] as? String ?? (parameters["format"] == nil ? "png" : nil) else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("format")
            }
            guard ["png", "jpeg"].contains(format) else {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter("format")
            }
            self.format = format
            let quality = try parameters["quality"].map { try Self.integer($0, name: "quality") } ?? 80
            self.quality = (0...100).contains(quality) ? quality : 80
            guard try Self.boolean(parameters["fromSurface"], name: "fromSurface", default: true) else {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter("fromSurface")
            }
            if try Self.boolean(parameters["optimizeForSpeed"], name: "optimizeForSpeed", default: false) {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter("optimizeForSpeed")
            }
            beyondViewport = try Self.boolean(
                parameters["captureBeyondViewport"], name: "captureBeyondViewport", default: false)
            guard let rawClip = parameters["clip"] else {
                rectangle = nil
                scale = 1
                return
            }
            guard let clip = rawClip as? [String: Any] else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("clip")
            }
            guard let scale = clip["scale"] as? NSNumber, CFGetTypeID(scale) != CFBooleanGetTypeID(),
                scale.doubleValue.isFinite, scale.doubleValue > 0
            else { throw BrowserChromeDebuggerProtocolError.invalidParameter("clip.scale") }
            self.scale = scale.doubleValue
            let x = try Self.integer(clip["x"], name: "clip.x")
            let y = try Self.integer(clip["y"], name: "clip.y")
            let width = try Self.integer(clip["width"], name: "clip.width")
            let height = try Self.integer(clip["height"], name: "clip.height")
            guard width > 0, height > 0 else { throw BrowserChromeDebuggerProtocolError.invalidParameter("clip size") }
            rectangle = ["x": x, "y": y, "width": width, "height": height, "coordinateSystem": "Page"]
        }

        static func integer(_ value: Any?, name: String) throws -> Int {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                number.doubleValue >= Double(Int32.min), number.doubleValue <= Double(Int32.max)
            else { throw BrowserChromeDebuggerProtocolError.invalidParameter(name) }
            return number.intValue
        }

        private static func boolean(_ value: Any?, name: String, default fallback: Bool) throws -> Bool {
            guard let value else { return fallback }
            guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter(name)
            }
            return number.boolValue
        }
    }
}
