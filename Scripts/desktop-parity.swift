// Operates on the two comparison processes printed by compare-desktop.py.
import AppKit
import CoreMedia
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ComparisonError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Gesture: String {
    case sidebar, palette, settings

    var key: CGKeyCode {
        switch self {
        case .sidebar: 1  // S
        case .palette: 37  // L
        case .settings: 43  // comma
        }
    }
}

enum CaptureInput {
    case shortcut(Gesture)
    case click(CGPoint)

    /// Coordinates are layout points measured from the captured content's upper left.
    func events(content: CGRect, windowsKeys: Bool) throws -> (CGEvent, CGEvent) {
        switch self {
        case .shortcut(let gesture):
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: gesture.key, keyDown: true),
                let up = CGEvent(keyboardEventSource: nil, virtualKey: gesture.key, keyDown: false)
            else { throw ComparisonError(message: "Could not create the comparison shortcut.") }
            down.flags = windowsKeys ? .maskControl : .maskCommand
            up.flags = down.flags
            return (down, up)
        case .click(let point):
            let location = CGPoint(x: content.minX + point.x, y: content.minY + point.y)
            guard content.contains(location),
                let down = CGEvent(
                    mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: location, mouseButton: .left),
                let up = CGEvent(
                    mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)
            else { throw ComparisonError(message: "Click coordinates must lie inside the captured content.") }
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
            return (down, up)
        }
    }

    static func point(_ argument: String) throws -> CaptureInput {
        let parts = argument.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]), x.isFinite, y.isFinite else {
            throw ComparisonError(message: "Specify a click position as X,Y in layout points.")
        }
        return .click(CGPoint(x: x, y: y))
    }
}

@MainActor
func window(of pid: pid_t, desktop: Bool) throws -> AXUIElement {
    var result: CFTypeRef?
    let app = AXUIElementCreateApplication(pid)
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &result) == .success,
        let windows = result as? [AXUIElement]
    else { throw ComparisonError(message: "Expected one browser window for PID \(pid).") }
    let candidates = windows.filter { window in
        guard desktop else { return true }
        var title: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success
            && title as? String == "Crest"
    }
    guard candidates.count == 1, let target = candidates.first else {
        throw ComparisonError(message: "Could not identify the comparison window for PID \(pid).")
    }
    return target
}

// Chromium app mode places a system title bar above the web viewport on macOS.
func desktopTitleBarHeight(_ window: AXUIElement) throws -> CGFloat {
    func position(_ element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        var point = CGPoint.zero
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID(),
            AXValueGetValue(value as! AXValue, .cgPoint, &point)
        else { return nil }
        return point
    }
    var children: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children) == .success,
        let groups = children as? [AXUIElement],
        let content = groups.first(where: {
            var role: CFTypeRef?
            return AXUIElementCopyAttributeValue($0, kAXRoleAttribute as CFString, &role) == .success
                && role as? String == kAXGroupRole
        }),
        let top = position(window), let viewport = position(content), viewport.y >= top.y
    else { throw ComparisonError(message: "Could not measure the Chromium content area.") }
    return viewport.y - top.y
}

@MainActor
func arrange(_ pids: [pid_t]) throws {
    guard let screen = NSScreen.main, let main = NSScreen.screens.first else {
        throw ComparisonError(message: "No display available.")
    }
    let usable = screen.visibleFrame
    let width = floor(usable.width / 2)
    let titleBar = try desktopTitleBarHeight(window(of: pids[1], desktop: true))
    let height = min(usable.height - titleBar, 900)
    for (index, pid) in pids.enumerated() {
        let target = try window(of: pid, desktop: index == 1)
        var size = CGSize(width: width, height: height + (index == 1 ? titleBar : 0))
        var point = CGPoint(
            x: usable.minX + CGFloat(index) * width, y: main.frame.maxY - usable.maxY + (index == 0 ? titleBar : 0))
        guard let dimensions = AXValueCreate(.cgSize, &size), let origin = AXValueCreate(.cgPoint, &point),
            AXUIElementSetAttributeValue(target, kAXSizeAttribute as CFString, dimensions) == .success,
            AXUIElementSetAttributeValue(target, kAXPositionAttribute as CFString, origin) == .success
        else { throw ComparisonError(message: "Could not position the comparison window for PID \(pid).") }
        _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    }
}

struct Frame {
    let time: Double
    let image: CGImage
}

final class WindowFrames: NSObject, SCStreamOutput {
    // MARK: - Variables

    let queue = DispatchQueue(label: "crest.comparison.frames")
    private(set) var frames: [Frame] = []

    // MARK: - Actions - Sampling

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sample.imageBuffer,
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
            let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue
        else { return }
        // Copy pixels off the capture surface so the compositor can reuse it immediately.
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard let bytes = CVPixelBufferGetBaseAddress(buffer),
            let provider = CGDataProvider(data: Data(bytes: bytes, count: stride * height) as CFData),
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                space: space,
                bitmapInfo: [.byteOrder32Little, CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)],
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return }
        frames.append(Frame(time: sample.presentationTimeStamp.seconds, image: image))
    }
}

@MainActor
func capture(pid: pid_t, input: CaptureInput, windowsKeys: Bool, folder: URL, duration: Int) async throws -> [Double] {
    guard let app = NSRunningApplication(processIdentifier: pid), app.activate(options: []) else {
        throw ComparisonError(message: "Could not activate PID \(pid).")
    }
    let target = try window(of: pid, desktop: windowsKeys)
    _ = AXUIElementPerformAction(target, kAXRaiseAction as CFString)
    try await Task.sleep(for: .milliseconds(350))
    let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
    let windows = content.windows.filter {
        $0.owningApplication?.processID == pid && $0.windowLayer == 0 && (!windowsKeys || $0.title == "Crest")
    }
    guard windows.count == 1, let window = windows.first else {
        throw ComparisonError(message: "Expected one visible browser window for PID \(pid).")
    }
    let inset = windowsKeys ? try desktopTitleBarHeight(target) : 0
    let viewport = CGRect(x: 0, y: inset, width: window.frame.width, height: window.frame.height - inset)
    let configuration = SCStreamConfiguration()
    configuration.width = Int(window.frame.width)
    configuration.height = Int(window.frame.height)
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 120)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.colorSpaceName = CGColorSpace.sRGB
    configuration.showsCursor = false
    configuration.ignoreShadowsSingleWindow = true
    let stream = SCStream(
        filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: nil)
    let output = WindowFrames()
    try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
    let contentFrame = viewport.offsetBy(dx: window.frame.minX, dy: window.frame.minY)
    let (down, up) = try input.events(content: contentFrame, windowsKeys: windowsKeys)
    let originalPointer = CGEvent(source: nil)?.location
    if case .click = input {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: down.location, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
    defer {
        if case .click = input, let originalPointer, CGEvent(source: nil)?.location == down.location {
            CGWarpMouseCursorPosition(originalPointer)
        }
    }
    try await stream.startCapture()
    try await Task.sleep(for: .milliseconds(250))
    if case .click = input {
        var hit: AXUIElement?
        var hitPID: pid_t = 0
        let result = AXUIElementCopyElementAtPosition(
            AXUIElementCreateSystemWide(), Float(down.location.x), Float(down.location.y), &hit)
        guard result == .success,
            let hit, AXUIElementGetPid(hit, &hitPID) == .success, hitPID == pid
        else {
            try await stream.stopCapture()
            throw ComparisonError(message: "The requested click is covered by another window.")
        }
    }
    let start = CMClockGetTime(CMClockGetHostTimeClock()).seconds
    switch input {
    case .shortcut:
        down.postToPid(pid)
        up.postToPid(pid)
    case .click:
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    try await Task.sleep(for: .milliseconds(duration))
    try await stream.stopCapture()
    let frames = output.queue.sync { output.frames }
    guard let before = frames.last(where: { $0.time <= start }) else {
        throw ComparisonError(message: "The recorder missed the initial frame for PID \(pid).")
    }
    let shown = [before] + frames.filter { $0.time > start }
    guard shown.count > 1 else {
        throw ComparisonError(message: "No new frames arrived after the shortcut for PID \(pid).")
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    for (index, frame) in shown.enumerated() {
        let file = folder.appendingPathComponent("\(index).png")
        guard
            let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ComparisonError(message: "Could not create \(file.path).")
        }
        guard let image = frame.image.cropping(to: viewport) else {
            throw ComparisonError(message: "Could not crop the capture to its viewport.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ComparisonError(message: "Could not save \(file.path).")
        }
    }
    return shown.map { ($0.time - start) * 1000 }
}

let arguments = Array(CommandLine.arguments.dropFirst())
do {
    guard arguments.count >= 3, let native = Int32(arguments[1]), let desktop = Int32(arguments[2]),
        native > 0, desktop > 0, native != desktop
    else {
        throw ComparisonError(
            message:
                "Pass arrange NATIVE_PID SVELTE_PID or capture NATIVE_PID SVELTE_PID GESTURE NEW_FOLDER."
        )
    }
    guard AXIsProcessTrusted() else {
        throw ComparisonError(message: "Window control needs macOS Accessibility access for this terminal.")
    }
    if arguments[0] == "arrange", arguments.count == 3 {
        for attempt in 0..<60 {
            do {
                try arrange([native, desktop])
                break
            } catch  where attempt < 59 {
                try await Task.sleep(for: .milliseconds(250))
            }
        }
    } else if arguments[0] == "capture" || arguments[0] == "capture-click" {
        let clicks = arguments[0] == "capture-click"
        let outputIndex = clicks ? 5 : 4
        guard arguments.count == outputIndex + 1 || arguments.count == outputIndex + 2 else {
            throw ComparisonError(
                message: "Pass a gesture or two X,Y positions, a new folder and optionally the duration in ms.")
        }
        let duration = arguments.count == outputIndex + 2 ? Int(arguments[outputIndex + 1]) : 750
        guard let duration, (100...2500).contains(duration) else {
            throw ComparisonError(message: "The capture duration must be between 100 and 2500 ms.")
        }
        let inputs: (CaptureInput, CaptureInput)
        if clicks {
            inputs = try (.point(arguments[3]), .point(arguments[4]))
        } else if let gesture = Gesture(rawValue: arguments[3]) {
            inputs = (.shortcut(gesture), .shortcut(gesture))
        } else {
            throw ComparisonError(message: "Choose sidebar, palette or settings.")
        }
        guard CGPreflightScreenCaptureAccess() else {
            throw ComparisonError(message: "Recording needs macOS Screen Recording access for this terminal.")
        }
        let folder = URL(fileURLWithPath: arguments[outputIndex], isDirectory: true).standardizedFileURL
        guard !FileManager.default.fileExists(atPath: folder.path) else {
            throw ComparisonError(message: "Choose a new capture folder.")
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let mac = try await capture(
            pid: native, input: inputs.0, windowsKeys: false, folder: folder.appendingPathComponent("native"),
            duration: duration)
        let ui = try await capture(
            pid: desktop, input: inputs.1, windowsKeys: true, folder: folder.appendingPathComponent("svelte"),
            duration: duration)
        let data = try JSONEncoder().encode(["native": mac, "svelte": ui])
        let template = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(
            "desktop-parity-viewer.html")
        let html = try String(contentsOf: template, encoding: .utf8).replacingOccurrences(
            of: "FRAME_TIMES", with: String(decoding: data, as: UTF8.self))
        try html.write(to: folder.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        print("Captured \(mac.count) native and \(ui.count) Svelte frames. Open \(folder.path)/index.html")
    } else {
        throw ComparisonError(message: "Expected arrange or capture with a supported gesture and output folder.")
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
