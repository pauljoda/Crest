import AppKit
import SwiftUI

@MainActor
final class BrowserWindowTransparencyHostView: NSView {
    var focusChanged: ((Bool) -> Void)?
    var isTransparencyEnabled: Bool {
        didSet {
            guard isTransparencyEnabled != oldValue else { return }
            configureAttachedWindow()
        }
    }

    private weak var configuredWindow: NSWindow?
    private var originalIsOpaque: Bool?
    private var originalBackgroundColor: NSColor?
    private var observers: [NSObjectProtocol] = []
    private var lastReportedFocus: Bool?

    init(isTransparencyEnabled: Bool = true) {
        self.isTransparencyEnabled = isTransparencyEnabled
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureAttachedWindow()
    }

    func configureAttachedWindow() {
        guard let window else { return }
        if configuredWindow !== window {
            restoreWindowBacking()
            configuredWindow = window
            originalIsOpaque = window.isOpaque
            originalBackgroundColor = window.backgroundColor
            observe(window)
        }

        reportFocus(window.isKeyWindow)
        if isTransparencyEnabled {
            if window.isOpaque {
                window.isOpaque = false
            }
            if window.backgroundColor != .clear {
                window.backgroundColor = .clear
            }
        } else {
            restoreBackingValues(on: window)
        }
    }

    func restoreWindowBacking() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        if let configuredWindow {
            restoreBackingValues(on: configuredWindow)
        }
        configuredWindow = nil
        originalIsOpaque = nil
        originalBackgroundColor = nil
        lastReportedFocus = nil
    }

    private func observe(_ window: NSWindow) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reportFocus(true) }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.reportFocus(false) }
            },
        ]
    }

    private func reportFocus(_ isFocused: Bool) {
        guard lastReportedFocus != isFocused else { return }
        lastReportedFocus = isFocused
        Task { @MainActor [weak self] in
            self?.focusChanged?(isFocused)
        }
    }

    private func restoreBackingValues(on window: NSWindow) {
        if let originalIsOpaque, window.isOpaque != originalIsOpaque {
            window.isOpaque = originalIsOpaque
        }
        if let originalBackgroundColor,
            window.backgroundColor != originalBackgroundColor
        {
            window.backgroundColor = originalBackgroundColor
        }
    }
}
