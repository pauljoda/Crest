import AppKit
import Foundation

/// Captures the inspected page through WebKit, without resizing its WKWebView
/// or moving the user's scroll position. This is not yet an extension endpoint.
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
        if options.format == "png" { return ["data": png.base64EncodedString()] }
        guard let bitmap = NSBitmapImageRep(data: png),
            let jpeg = bitmap.representation(
                using: .jpeg, properties: [.compressionFactor: Double(options.quality) / 100])
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        return ["data": jpeg.base64EncodedString()]
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
                return
            }
            guard let clip = rawClip as? [String: Any] else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("clip")
            }
            guard beyondViewport else {
                throw BrowserChromeDebuggerProtocolError.unsupportedParameter("clip with captureBeyondViewport=false")
            }
            let scale = try Self.integer(clip["scale"], name: "clip.scale")
            guard scale == 1 else { throw BrowserChromeDebuggerProtocolError.unsupportedParameter("clip.scale") }
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
