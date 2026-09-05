// Standalone investigation tool; deliberately excluded from the Crest app target.
import AppKit
import WebKit

@MainActor
final class Probe: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private let enablesNative = CommandLine.arguments.contains("--enable-native")
    private let usesFlyout = CommandLine.arguments.contains("--flyout")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.inactiveSchedulingPolicy = .suspend
        let selector = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        let available = configuration.preferences.responds(to: selector)
        log(
            "configuration",
            [
                "privateSetterAvailable": available, "enableNative": enablesNative, "flyout": usesFlyout,
                "inactiveSchedulingPolicy": "suspend",
                "os": ProcessInfo.processInfo.operatingSystemVersionString,
            ])
        if enablesNative {
            guard available else {
                finish(2)
                return
            }
            typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
            let setter = unsafeBitCast(configuration.preferences.method(for: selector), to: Setter.self)
            setter(configuration.preferences, selector, true)
        }
        configuration.userContentController.add(self, name: "probe")
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 580), configuration: configuration)
        webView.navigationDelegate = self
        window = NSWindow(
            contentRect: webView.frame, styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Crest desktop PiP probe — \(enablesNative ? "enabled" : "baseline")"
        window.level = .floating
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let fixture = Bundle.main.resourceURL!.appendingPathComponent("probe.html")
        webView.loadFileURL(fixture, allowingReadAccessTo: fixture.deletingLastPathComponent())
        Task {
            try? await Task.sleep(for: .seconds(30))
            finish(3)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await run() }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        log("page", message.body)
    }

    private func run() async {
        do {
            _ = try await webView.callAsyncJavaScript(
                "await window.ready; return true;", arguments: [:], in: nil, contentWorld: .page)
            _ = try await webView.evaluateJavaScript("video.play(); null")
            try await Task.sleep(for: .milliseconds(400))
            let initial = try await snapshot("playing")
            if usesFlyout {
                try await runFlyout(initial: initial)
                finish(0)
                return
            }
            _ = try await webView.evaluateJavaScript("attemptNative('standard'); null")
            try await Task.sleep(for: .seconds(2))
            let standard = try await snapshot("standard-result")
            if try await webView.evaluateJavaScript("video.webkitPresentationMode === 'picture-in-picture'") as? Bool
                != true
            {
                _ = try await webView.evaluateJavaScript("attemptNative('prefixed'); null")
                try await Task.sleep(for: .seconds(2))
                try await snapshot("prefixed-result")
            }
            let entered =
                try await webView.evaluateJavaScript("video.webkitPresentationMode === 'picture-in-picture'") as? Bool
                == true
            log("native-entered", entered)
            let sawWindow = logWindows()
            if entered {
                webView.removeFromSuperview()
                window.orderOut(nil)
                try await Task.sleep(for: .seconds(2))
                let detached = try await snapshot("source-detached")
                try require(
                    detached["identity"] as? String == initial["identity"] as? String, "same document after detach")
                try require(
                    (detached["decodedFrames"] as? Int ?? 0) > (standard["decodedFrames"] as? Int ?? 0),
                    "video frames advance while source detached")
                logWindows()
                _ = try await webView.evaluateJavaScript("video.pause(); video.currentTime = 1; null")
                try await snapshot("paused-and-seeked")
                _ = try await webView.evaluateJavaScript("video.play(); null")
                window.contentView = webView
                window.makeKeyAndOrderFront(nil)
                _ = try await webView.evaluateJavaScript("video.webkitSetPresentationMode('inline'); null")
                try await Task.sleep(for: .seconds(1))
                let returned = try await snapshot("returned-inline")
                try require(
                    returned["mode"] as? String == "inline" && returned["elementIsPiP"] as? Bool == false,
                    "native PiP exits")
                try require(
                    returned["identity"] as? String == initial["identity"] as? String, "same document after return")
            }
            if enablesNative { try require(sawWindow, "system PiP window is on screen") }
            if !enablesNative { try require(!entered, "baseline reproduces disabled native PiP") }
            finish(enablesNative && !entered ? 1 : 0)
        } catch {
            log("error", String(describing: error))
            finish(2)
        }
    }

    @discardableResult
    private func snapshot(_ phase: String) async throws -> [String: Any] {
        let value = try await webView.evaluateJavaScript("state()") as? [String: Any] ?? [:]
        log(phase, value)
        return value
    }

    private func runFlyout(initial: [String: Any]) async throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: 480, height: 270),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Crest floating video probe"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = NSSize(width: 16, height: 9)
        _ = try await webView.evaluateJavaScript("enterFlyout(); null")
        webView.removeFromSuperview()
        panel.contentView = webView
        panel.orderFrontRegardless()
        window.orderOut(nil)
        try await Task.sleep(for: .seconds(2))
        let floating = try await snapshot("flyout-playing")
        try require(webView.window === panel && panel.isVisible, "same web view is hosted in visible panel")
        try require(floating["identity"] as? String == initial["identity"] as? String, "flyout preserves document")
        try require(
            (floating["decodedFrames"] as? Int ?? 0) > (initial["decodedFrames"] as? Int ?? 0),
            "flyout video frames advance")
        _ = try await webView.evaluateJavaScript("video.pause(); video.currentTime = 1; null")
        let paused = try await snapshot("flyout-paused")
        try require(paused["paused"] as? Bool == true, "flyout pause reaches original video")
        webView.removeFromSuperview()
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        panel.orderOut(nil)
        _ = try await webView.evaluateJavaScript("exitFlyout(); video.play(); null")
        try await Task.sleep(for: .seconds(1))
        let returned = try await snapshot("flyout-returned")
        try require(
            returned["identity"] as? String == initial["identity"] as? String, "flyout returns original document")
        try require(returned["flyoutStyled"] as? Bool == false, "flyout styles removed")
    }

    private func require(_ condition: Bool, _ name: String) throws {
        log("check", ["name": name, "passed": condition])
        if !condition { throw NSError(domain: "CrestPiPProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
    }

    @discardableResult
    private func logWindows() -> Bool {
        let windows =
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let pipWindows = windows.filter {
            let owner = $0[kCGWindowOwnerName as String] as? String ?? ""
            return owner == "PIPAgent" || owner.localizedCaseInsensitiveContains("picture in picture")
        }
        log(
            "pip-windows",
            pipWindows.map {
                [
                    "owner": $0[kCGWindowOwnerName as String] ?? "", "id": $0[kCGWindowNumber as String] ?? 0,
                    "bounds": $0[kCGWindowBounds as String] ?? [:],
                ]
            })
        if CommandLine.arguments.contains("--capture"),
            let id = pipWindows.first?[kCGWindowNumber as String] as? Int
        {
            let destination = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("native-pip.png")
                .path
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(id), destination]
            do {
                try capture.run()
                capture.waitUntilExit()
                log("capture", ["path": destination, "status": capture.terminationStatus])
            } catch { log("capture-error", String(describing: error)) }
        }
        return !pipWindows.isEmpty
    }

    private func log(_ phase: String, _ value: Any) {
        let object: [String: Any] = ["phase": phase, "value": value]
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            let line = String(data: data, encoding: .utf8)
        {
            print(line)
            fflush(stdout)
        }
    }

    private func finish(_ code: Int32) {
        log("exit", code)
        Darwin.exit(code)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = Probe()
app.delegate = delegate
app.run()
