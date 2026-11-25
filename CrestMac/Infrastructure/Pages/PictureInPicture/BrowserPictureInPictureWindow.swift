import AppKit
import SwiftUI

/// One floating surface for video from either engine. Window movement and
/// resizing are presentation state; playback and source activation stay with
/// the engine that supplied the view.
@MainActor
final class BrowserPictureInPictureWindow: NSPanel {
    // MARK: - Types

    private struct PointerSample {
        let location: CGPoint
        let time: TimeInterval
    }

    private struct Drag {
        let original: CGRect
        let start: CGPoint
        let horizontalEdge: CGFloat
        let verticalEdge: CGFloat
        var samples: [PointerSample] = []

        var resizes: Bool { horizontalEdge != 0 || verticalEdge != 0 }

        mutating func record(_ sample: PointerSample) {
            samples.removeAll { sample.time - $0.time > 0.12 }
            samples.append(sample)
        }

        /// The final part of the gesture determines a throw. Waiting before
        /// releasing cancels a throw, even if the window travelled far.
        func flick(at release: PointerSample) -> CGVector? {
            guard let last = samples.last, release.time - last.time < 0.075,
                let first = samples.first(where: { release.time - $0.time <= 0.12 })
            else { return nil }
            let elapsed = release.time - first.time
            let dx = release.location.x - first.location.x
            let dy = release.location.y - first.location.y
            let distance = hypot(dx, dy)
            guard elapsed > 0, distance >= 42, distance / elapsed >= 950 else { return nil }
            return CGVector(dx: dx / elapsed, dy: dy / elapsed)
        }
    }

    private final class PointerSurface: NSView {
        weak var player: BrowserPictureInPictureWindow?
        weak var controls: NSView?
        private var tracking: NSTrackingArea?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let next = NSTrackingArea(
                rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
            addTrackingArea(next)
            tracking = next
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard bounds.contains(local) else { return nil }
            if let controls, controls.alphaValue > 0, controls.frame.contains(local) {
                return controls.hitTest(local) ?? controls
            }
            return self
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseEntered(with event: NSEvent) { player?.setPointerInside(true) }
        override func mouseExited(with event: NSEvent) { player?.setPointerInside(false) }
        override func mouseDown(with event: NSEvent) {
            player?.beginDrag(at: convert(event.locationInWindow, from: nil), time: event.timestamp)
        }
        override func mouseDragged(with event: NSEvent) { player?.moveDrag(at: event.timestamp) }
        override func mouseUp(with event: NSEvent) { player?.endDrag(at: event.timestamp) }
    }

    // MARK: - Static Variables

    private static let inset: CGFloat = CrestSpacing.medium
    private static let resizeMargin: CGFloat = 6
    private static let initialWidth: CGFloat = 360
    private static let minimumWidth: CGFloat = 180

    // MARK: - Variables

    let videoContainer = NSView()
    private let surface = PointerSurface()
    private var controls: NSHostingView<BrowserPictureInPictureControls>?
    private weak var video: NSView?
    private var aspect: CGFloat
    private var drag: Drag?
    private var destination: CGRect
    private var isPresenting = false
    private var pointerIsInside = false
    var onPlayback: (Bool) -> Void = { _ in }
    var onRestore: () -> Void = {}
    var onClose: () -> Void = {}

    var isPlaying: Bool {
        didSet {
            if isPlaying != oldValue { controls?.rootView = controlContent }
        }
    }

    var restingFrame: CGRect { isPresenting ? destination : frame }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // MARK: - Initializers

    init(videoSize: CGSize, restingFrame: CGRect?, sourceScreen: NSScreen?, isPlaying: Bool) {
        let workArea =
            NSScreen.screens.first {
                guard let restingFrame else { return false }
                return $0.frame.contains(CGPoint(x: restingFrame.midX, y: restingFrame.midY))
            }?.visibleFrame ?? sourceScreen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 960, height: 640)
        let aspect = Self.aspect(of: videoSize)
        self.aspect = aspect
        self.isPlaying = isPlaying
        let width = min(restingFrame?.width ?? Self.initialWidth, workArea.width, workArea.height * aspect)
        let size = CGSize(width: width, height: width / aspect)
        let start =
            restingFrame?.origin
            ?? CGPoint(
                x: workArea.maxX - size.width - Self.inset, y: workArea.minY + Self.inset)
        destination = Self.contained(CGRect(origin: start, size: size), in: workArea)
        super.init(
            contentRect: destination, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = String(localized: "Picture in Picture")
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .participatesInCycle, .canJoinAllApplications]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        surface.frame = CGRect(origin: .zero, size: destination.size)
        surface.player = self
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.black.cgColor
        surface.layer?.cornerRadius = CrestRadius.control
        surface.layer?.masksToBounds = true
        videoContainer.frame = surface.bounds
        videoContainer.autoresizingMask = [.width, .height]
        surface.addSubview(videoContainer)
        contentView = surface

        let controls = NSHostingView(rootView: controlContent)
        let sizeOfControls = controls.fittingSize
        controls.frame = CGRect(
            x: (surface.bounds.width - sizeOfControls.width) / 2,
            y: surface.bounds.height - sizeOfControls.height - Self.inset,
            width: sizeOfControls.width, height: sizeOfControls.height)
        controls.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        controls.alphaValue = 0
        surface.addSubview(controls)
        surface.controls = controls
        self.controls = controls
    }

    // MARK: - Actions - Presentation

    func present(_ view: NSView, from sourceFrame: CGRect?) {
        video = view
        let fliesFromSource =
            sourceFrame.map { !$0.isEmpty } == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if fliesFromSource, let sourceFrame {
            setFrame(sourceFrame, display: false)
            isPresenting = true
        }
        videoContainer.addSubview(view)
        view.frame = videoContainer.bounds
        view.autoresizingMask = [.width, .height]
        NSApp.addWindowsItem(self, title: title, filename: false)
        orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self, let video else { return }
            // WebKit signals entry on the first container resize after
            // present returns, including when the animation is reduced.
            video.resize(withOldSuperviewSize: videoContainer.bounds.size)
            if isPresenting {
                setFrame(destination, display: true, animate: true)
                isPresenting = false
            }
            setPointerInside(frame.contains(NSEvent.mouseLocation))
        }
    }

    func dismiss() {
        NSApp.removeWindowsItem(self)
        orderOut(nil)
        video?.removeFromSuperview()
        video = nil
    }

    func setVideoSize(_ size: CGSize) {
        let next = Self.aspect(of: size)
        guard next != aspect else { return }
        aspect = next
        if let visible = screen?.visibleFrame {
            let rect = resized(restingFrame, to: restingFrame.width, in: visible)
            destination = rect
            if !isPresenting { setFrame(rect, display: true) }
        }
    }

    private var controlContent: BrowserPictureInPictureControls {
        BrowserPictureInPictureControls(
            isPlaying: isPlaying,
            playPause: { [weak self] in
                guard let self else { return }
                onPlayback(!isPlaying)
            },
            restore: { [weak self] in self?.onRestore() },
            close: { [weak self] in self?.onClose() })
    }

    override func becomeKey() {
        super.becomeKey()
        updateControlVisibility()
        recalculateKeyViewLoop()
    }

    override func resignKey() {
        super.resignKey()
        updateControlVisibility()
    }

    private func setPointerInside(_ inside: Bool) {
        pointerIsInside = inside
        updateControlVisibility()
    }

    private func updateControlVisibility() {
        controls?.alphaValue = pointerIsInside || isKeyWindow ? 1 : 0
    }

    // MARK: - Actions - Pointer

    private func beginDrag(at point: CGPoint, time: TimeInterval) {
        let margin = Self.resizeMargin
        let horizontal: CGFloat = point.x <= margin ? -1 : point.x >= frame.width - margin ? 1 : 0
        let vertical: CGFloat = point.y <= margin ? -1 : point.y >= frame.height - margin ? 1 : 0
        let start = NSEvent.mouseLocation
        drag = Drag(
            original: frame, start: start, horizontalEdge: horizontal, verticalEdge: vertical,
            samples: [PointerSample(location: start, time: time)])
    }

    private func moveDrag(at time: TimeInterval) {
        guard var drag else { return }
        let mouse = NSEvent.mouseLocation
        drag.record(PointerSample(location: mouse, time: time))
        self.drag = drag
        let dx = mouse.x - drag.start.x
        let dy = mouse.y - drag.start.y
        if drag.resizes {
            guard let visible = screen?.visibleFrame else { return }
            let horizontal = dx * drag.horizontalEdge
            let vertical = dy * drag.verticalEdge * aspect
            let delta = abs(horizontal) >= abs(vertical) ? horizontal : vertical
            let rect = resized(
                drag.original, to: drag.original.width + delta, in: visible,
                horizontal: drag.horizontalEdge, vertical: drag.verticalEdge)
            setFrame(rect, display: true)
        } else {
            setFrameOrigin(CGPoint(x: drag.original.minX + dx, y: drag.original.minY + dy))
        }
    }

    private func endDrag(at time: TimeInterval) {
        guard let drag else { return }
        self.drag = nil
        let mouse = NSEvent.mouseLocation
        guard let visible = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen)?.visibleFrame else {
            return
        }
        let dropped =
            drag.resizes ? frame : drag.original.offsetBy(dx: mouse.x - drag.start.x, dy: mouse.y - drag.start.y)
        let settled = resized(dropped, to: dropped.width, in: visible)
        guard !drag.resizes, let velocity = drag.flick(at: PointerSample(location: mouse, time: time)) else {
            setFrame(settled, display: true)
            return
        }
        let horizontal = abs(velocity.dx) >= abs(velocity.dy) * 0.25 ? velocity.dx > 0 : settled.midX > visible.midX
        let vertical = abs(velocity.dy) >= abs(velocity.dx) * 0.25 ? velocity.dy > 0 : settled.midY > visible.midY
        let x = horizontal ? visible.maxX - settled.width - Self.inset : visible.minX + Self.inset
        let y = vertical ? visible.maxY - settled.height - Self.inset : visible.minY + Self.inset
        setFrame(
            Self.contained(CGRect(origin: CGPoint(x: x, y: y), size: settled.size), in: visible), display: true,
            animate: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    // MARK: - Actions - Geometry

    private func resized(
        _ frame: CGRect, to width: CGFloat, in bounds: CGRect,
        horizontal: CGFloat = 0, vertical: CGFloat = 0
    ) -> CGRect {
        let maximum = min(bounds.width, bounds.height * aspect)
        let w = min(max(Self.minimumWidth, width), maximum)
        let h = w / aspect
        let x = frame.midX - w / 2 + horizontal * (w - frame.width) / 2
        let y = frame.midY - h / 2 + vertical * (h - frame.height) / 2
        return Self.contained(CGRect(x: x, y: y, width: w, height: h), in: bounds)
    }

    private static func contained(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        CGRect(
            x: max(bounds.minX, min(rect.minX, bounds.maxX - rect.width)),
            y: max(bounds.minY, min(rect.minY, bounds.maxY - rect.height)),
            width: rect.width, height: rect.height)
    }

    private static func aspect(of size: CGSize) -> CGFloat {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }
}
