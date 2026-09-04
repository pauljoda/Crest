import AppKit
import Foundation
import WebKit

/// Delivers CDP input to the inspected page as real AppKit events.
///
/// WebKit's own protocol has no input domain, so a synthetic event is the only
/// way a protocol client can click or type. That makes this the one translator
/// that acts on the page as a user rather than describing it: it hands the web
/// view the same `NSEvent` a trackpad or keyboard would, so the page's own
/// hit-testing, focus, and gesture recognition decide what happens.
@MainActor
final class BrowserChromeDebuggerInput {
    private weak var webView: WKWebView?
    private var eventNumber = 0

    init(webView: WKWebView) {
        self.webView = webView
    }

    func execute(_ method: String, parameters: [String: Any]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard let webView else { throw BrowserWebInspectorProtocolError.notConnected }
        switch method {
        case "Input.dispatchMouseEvent":
            try dispatchMouse(parameters, in: webView)
        case "Input.dispatchKeyEvent":
            try dispatchKey(parameters, in: webView)
        case "Input.insertText":
            guard let text = parameters["text"] as? String else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("text")
            }
            insert(text, in: webView)
        default:
            throw BrowserChromeDebuggerProtocolError.unsupportedCommand(method)
        }
        return [:]
    }

    // MARK: - Mouse

    private func dispatchMouse(_ parameters: [String: Any], in webView: WKWebView) throws {
        let point = try viewPoint(parameters, in: webView)
        let flags = try BrowserChromeDebuggerKeyCodes.modifierFlags(parameters["modifiers"])
        let button = try mouseButton(parameters["button"])
        guard let type = parameters["type"] as? String else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("type")
        }
        if type == "mouseWheel" {
            try dispatchWheel(parameters, at: point, flags: flags, in: webView)
            return
        }
        let clickCount =
            try parameters["clickCount"].map {
                try BrowserChromeDebuggerValues.integer($0, name: "clickCount")
            } ?? (type == "mouseMoved" ? 0 : 1)
        guard clickCount >= 0, clickCount <= 3 else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("clickCount")
        }
        let held = try heldButton(parameters, fallback: button)
        let eventType: NSEvent.EventType
        switch (type, type == "mouseMoved" ? held : button) {
        case ("mousePressed", .left): eventType = .leftMouseDown
        case ("mousePressed", .right): eventType = .rightMouseDown
        case ("mousePressed", _): eventType = .otherMouseDown
        case ("mouseReleased", .left): eventType = .leftMouseUp
        case ("mouseReleased", .right): eventType = .rightMouseUp
        case ("mouseReleased", _): eventType = .otherMouseUp
        case ("mouseMoved", .none): eventType = .mouseMoved
        case ("mouseMoved", .left): eventType = .leftMouseDragged
        case ("mouseMoved", .right): eventType = .rightMouseDragged
        case ("mouseMoved", _): eventType = .otherMouseDragged
        default: throw BrowserChromeDebuggerProtocolError.unsupportedParameter("type")
        }
        eventNumber += 1
        guard
            let event = NSEvent.mouseEvent(
                with: eventType, location: windowPoint(point, in: webView), modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: webView.window?.windowNumber ?? 0,
                context: nil, eventNumber: eventNumber, clickCount: clickCount,
                pressure: eventType == .leftMouseDown ? 1 : 0)
        else { throw BrowserChromeDebuggerProtocolError.invalidParameter("type") }
        switch eventType {
        case .leftMouseDown: webView.mouseDown(with: event)
        case .leftMouseUp: webView.mouseUp(with: event)
        case .rightMouseDown: webView.rightMouseDown(with: event)
        case .rightMouseUp: webView.rightMouseUp(with: event)
        case .otherMouseDown: webView.otherMouseDown(with: event)
        case .otherMouseUp: webView.otherMouseUp(with: event)
        case .mouseMoved: webView.mouseMoved(with: event)
        case .leftMouseDragged: webView.mouseDragged(with: event)
        case .rightMouseDragged: webView.rightMouseDragged(with: event)
        default: webView.otherMouseDragged(with: event)
        }
    }

    /// AppKit has no constructor for a scroll event, so the wheel goes through
    /// CoreGraphics and is retargeted at the web view's own window.
    private func dispatchWheel(
        _ parameters: [String: Any], at point: NSPoint, flags: NSEvent.ModifierFlags, in webView: WKWebView
    ) throws {
        let scale = zoomScale(of: webView)
        let deltaX = try BrowserChromeDebuggerValues.number(parameters["deltaX"] ?? 0, name: "deltaX") * scale
        let deltaY = try BrowserChromeDebuggerValues.number(parameters["deltaY"] ?? 0, name: "deltaY") * scale
        // CDP scroll deltas point the way the content moves away from the
        // viewport; AppKit's point the way the content moves with the finger.
        guard
            let scroll = CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                wheel1: Int32(clamping: Int(-deltaY.rounded())), wheel2: Int32(clamping: Int(-deltaX.rounded())),
                wheel3: 0)
        else { throw BrowserChromeDebuggerProtocolError.invalidResult }
        scroll.flags = CGEventFlags(rawValue: UInt64(flags.rawValue))
        // An `NSEvent` built from a `CGEvent` belongs to no window, so AppKit
        // reports its screen location as `locationInWindow` — which is the
        // coordinate space WebKit converts from. Placing the CoreGraphics
        // location so that flip lands on the intended window point is what
        // makes the wheel arrive where the client aimed it.
        let inWindow = windowPoint(point, in: webView)
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? inWindow.y
        scroll.location = CGPoint(x: inWindow.x, y: primaryHeight - inWindow.y)
        guard let event = NSEvent(cgEvent: scroll) else {
            throw BrowserChromeDebuggerProtocolError.invalidResult
        }
        webView.scrollWheel(with: event)
    }

    private enum MouseButton { case none, left, middle, right, other }

    private func mouseButton(_ value: Any?) throws -> MouseButton {
        switch value as? String {
        case nil, "none": return .none
        case "left": return .left
        case "middle": return .middle
        case "right": return .right
        case "back", "forward": return .other
        default: throw BrowserChromeDebuggerProtocolError.invalidParameter("button")
        }
    }

    /// A drag reports its held buttons in the `buttons` bitmask rather than in
    /// `button`, which CDP leaves as `none` while the pointer moves.
    private func heldButton(_ parameters: [String: Any], fallback: MouseButton) throws -> MouseButton {
        guard let value = parameters["buttons"] else { return fallback }
        let bits = try BrowserChromeDebuggerValues.integer(value, name: "buttons")
        guard bits >= 0, bits < 32 else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("buttons")
        }
        if bits & 1 != 0 { return .left }
        if bits & 2 != 0 { return .right }
        if bits & 4 != 0 { return .middle }
        return bits == 0 ? .none : .other
    }

    // MARK: - Keyboard

    private func dispatchKey(_ parameters: [String: Any], in webView: WKWebView) throws {
        guard let type = parameters["type"] as? String,
            ["keyDown", "keyUp", "rawKeyDown", "char"].contains(type)
        else { throw BrowserChromeDebuggerProtocolError.invalidParameter("type") }
        let flags = try BrowserChromeDebuggerKeyCodes.modifierFlags(parameters["modifiers"])
        let key = parameters["key"] as? String
        let code = parameters["code"] as? String
        let text = parameters["text"] as? String
        // A `char` event carries only the character it produced, which is what
        // text insertion means; there is no AppKit event for a bare keypress.
        if type == "char" {
            let characters = BrowserChromeDebuggerKeyCodes.characters(text: text, key: key, code: code)
            guard !characters.isEmpty else {
                throw BrowserChromeDebuggerProtocolError.invalidParameter("text")
            }
            insert(characters, in: webView)
            return
        }
        let virtualKeyCode =
            try nativeKeyCode(parameters)
            ?? BrowserChromeDebuggerKeyCodes.virtualKeyCode(code: code, key: key)
        guard let virtualKeyCode else {
            throw BrowserChromeDebuggerProtocolError.unsupportedParameter("code")
        }
        // Chrome separates `keyDown` from `rawKeyDown` by whether a character
        // follows; AppKit has one key-down event and lets WebKit decide. Both
        // therefore deliver the same event: withholding the characters instead
        // would strip the key of its identity and arrive as a dead key.
        let characters = BrowserChromeDebuggerKeyCodes.characters(text: text, key: key, code: code)
        let unmodified = parameters["unmodifiedText"] as? String ?? characters
        guard
            let event = NSEvent.keyEvent(
                with: type == "keyUp" ? .keyUp : .keyDown, location: .zero, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: webView.window?.windowNumber ?? 0,
                context: nil, characters: characters, charactersIgnoringModifiers: unmodified,
                isARepeat: try BrowserChromeDebuggerValues.boolean("autoRepeat", in: parameters),
                keyCode: virtualKeyCode)
        else { throw BrowserChromeDebuggerProtocolError.invalidParameter("code") }
        if type == "keyUp" {
            webView.keyUp(with: event)
        } else {
            webView.keyDown(with: event)
        }
    }

    private func nativeKeyCode(_ parameters: [String: Any]) throws -> UInt16? {
        guard let value = parameters["nativeVirtualKeyCode"] else { return nil }
        let code = try BrowserChromeDebuggerValues.integer(value, name: "nativeVirtualKeyCode")
        guard code >= 0, code <= 0xFFFF else {
            throw BrowserChromeDebuggerProtocolError.invalidParameter("nativeVirtualKeyCode")
        }
        return UInt16(code)
    }

    /// Text insertion goes through the same text-input path a keyboard layout
    /// uses, so composed and multi-character text arrives whole.
    private func insert(_ text: String, in webView: WKWebView) {
        guard let client = webView as? NSTextInputClient else {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: webView.window?.windowNumber ?? 0,
                context: nil, characters: text, charactersIgnoringModifiers: text, isARepeat: false, keyCode: 0)
            if let event { webView.keyDown(with: event) }
            return
        }
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    // MARK: - Geometry

    /// CDP coordinates are CSS pixels measured from the viewport's top-left.
    /// AppKit's are points measured from the view's bottom-left, so both the
    /// zoom the user chose and the flipped axis have to be undone here.
    private func viewPoint(_ parameters: [String: Any], in webView: WKWebView) throws -> NSPoint {
        let x = try BrowserChromeDebuggerValues.number(parameters["x"] ?? 0, name: "x")
        let y = try BrowserChromeDebuggerValues.number(parameters["y"] ?? 0, name: "y")
        let scale = zoomScale(of: webView)
        let bounds = webView.bounds
        let scaled = NSPoint(x: bounds.minX + x * scale, y: bounds.minY + y * scale)
        return webView.isFlipped ? scaled : NSPoint(x: scaled.x, y: bounds.maxY - y * scale)
    }

    private func windowPoint(_ point: NSPoint, in webView: WKWebView) -> NSPoint {
        webView.convert(point, to: nil)
    }

    /// Page zoom and pinch magnification both change how many points a CSS
    /// pixel covers. A magnified page anchored away from the origin is not
    /// compensated: Crest never sets a magnification anchor for a web page.
    private func zoomScale(of webView: WKWebView) -> CGFloat {
        let zoom = webView.pageZoom > 0 ? webView.pageZoom : 1
        let magnification = webView.magnification > 0 ? webView.magnification : 1
        return zoom * magnification
    }
}
