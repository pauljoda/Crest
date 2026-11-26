import AppKit
import Observation
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
        let visibleFrame: CGRect
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

    private struct FrameAnimation {
        let from: CGRect
        let to: CGRect
        let startTime: CFTimeInterval
        let duration: CFTimeInterval
        let completion: @MainActor () -> Void
    }

    /// Breaks the retain cycle between `CADisplayLink` and the window.
    @MainActor
    private final class DisplayLinkTarget: NSObject {
        weak var window: BrowserPictureInPictureWindow?

        init(window: BrowserPictureInPictureWindow) {
            self.window = window
        }

        @objc func step(_ link: CADisplayLink) {
            window?.stepFrameAnimation(link)
        }
    }

    private final class PointerSurface: NSView {
        weak var player: BrowserPictureInPictureWindow?
        weak var controls: NSView?
        private var tracking: NSTrackingArea?

        override func layout() {
            super.layout()
            player?.layoutContent()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let next = NSTrackingArea(
                rect: .zero,
                options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
                owner: self)
            addTrackingArea(next)
            tracking = next
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            guard bounds.contains(local) else { return nil }
            if let controls, player?.controlsVisible == true, controls.alphaValue > 0.01,
                controls.frame.contains(local)
            {
                return controls.hitTest(local) ?? controls
            }
            return self
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseEntered(with event: NSEvent) {
            player?.setPointerInside(true)
            updateResizeCursor(with: event)
        }
        override func mouseExited(with event: NSEvent) {
            player?.setPointerInside(false)
            if player?.drag?.resizes != true { NSCursor.arrow.set() }
        }
        override func mouseMoved(with event: NSEvent) { updateResizeCursor(with: event) }
        private func updateResizeCursor(with event: NSEvent) {
            player?.resizeCursor(at: convert(event.locationInWindow, from: nil)).set()
        }
        override func mouseDown(with event: NSEvent) {
            player?.beginDrag(at: convert(event.locationInWindow, from: nil), time: event.timestamp)
        }
        override func mouseDragged(with event: NSEvent) { player?.moveDrag(at: event.timestamp) }
        override func mouseUp(with event: NSEvent) { player?.endDrag(at: event.timestamp) }
    }

    // MARK: - Static Variables

    static let inset: CGFloat = CrestSpacing.medium
    private static let resizeMargin: CGFloat = 6
    private static let initialWidth: CGFloat = 360
    static let minimumWidth: CGFloat = 180
    private static let flyDuration: CFTimeInterval = 0.26
    private static let settleDuration: CFTimeInterval = 0.18
    private static let controlsFadeDuration: TimeInterval = 0.14

    // MARK: - Variables

    let videoContainer = NSView()
    private let surface = PointerSurface()
    private let backdrop = NSHostingView(rootView: BrowserWindowAtmosphere(space: nil))
    private var controls: NSHostingView<BrowserPictureInPictureControls>?
    private var frameAppearance: BrowserDeviceAppearanceStore.PictureInPictureAppearance
    private var borderWidth: CGFloat { frameAppearance.borderWidth }
    private var refreshPending = false
    private weak var video: NSView?
    private var aspect: CGFloat
    private var pendingAspectReconcile = false
    private var drag: Drag?
    private var destination: CGRect
    private var frameAnimation: FrameAnimation?
    private var displayLink: CADisplayLink?
    private var isPresenting = false
    private var pointerIsInside = false
    private var controlsVisible = false
    var onPlayback: (Bool) -> Void = { _ in }
    var onRestore: () -> Void = {}
    var onSettings: () -> Void = {}
    var onClose: () -> Void = {}

    var isPlaying: Bool {
        didSet {
            if isPlaying != oldValue { controls?.rootView = controlContent }
        }
    }

    var restingFrame: CGRect { isPresenting || frameAnimation != nil ? destination : frame }

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
        let appearance = BrowserDeviceAppearanceStore.shared.pictureInPictureAppearance
        self.aspect = aspect
        frameAppearance = appearance
        self.isPlaying = isPlaying
        let border = appearance.borderWidth * 2
        let width = min(
            restingFrame?.width ?? Self.initialWidth, workArea.width, (workArea.height - border) * aspect + border)
        let size = CGSize(width: width, height: (width - border) / aspect + border)
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
        surface.layer?.masksToBounds = true
        backdrop.frame = surface.bounds
        surface.addSubview(backdrop)
        videoContainer.wantsLayer = true
        videoContainer.layer?.backgroundColor = NSColor.black.cgColor
        videoContainer.layer?.masksToBounds = true
        surface.addSubview(videoContainer)
        contentView = surface

        let controls = NSHostingView(rootView: controlContent)
        let sizeOfControls = controls.fittingSize
        controls.frame = CGRect(
            x: round((surface.bounds.width - sizeOfControls.width) / 2),
            y: round(surface.bounds.height - sizeOfControls.height - Self.inset - borderWidth),
            width: sizeOfControls.width, height: sizeOfControls.height)
        controls.alphaValue = 0
        surface.addSubview(controls)
        surface.controls = controls
        self.controls = controls
        layoutContent()
        observeAppearance()
    }

    // MARK: - Actions - Presentation

    func present(_ view: NSView, from sourceFrame: CGRect?) {
        cancelFrameAnimation()
        video = view
        let fliesFromSource =
            sourceFrame.map { !$0.isEmpty } == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if fliesFromSource, let sourceFrame {
            applyFrameWithoutActions(sourceFrame.insetBy(dx: -borderWidth, dy: -borderWidth))
            isPresenting = true
        }
        videoContainer.addSubview(view)
        view.autoresizingMask = [.width, .height]
        layoutContent()
        NSApp.addWindowsItem(self, title: title, filename: false)
        orderFrontRegardless()

        DispatchQueue.main.async { [weak self] in
            guard let self, video != nil else { return }
            if isPresenting {
                animateFrame(to: destination, duration: Self.flyDuration) { [weak self] in
                    guard let self else { return }
                    isPresenting = false
                    // WebKit acknowledges the first container resize after entry.
                    // Report the settled video bounds once the flight finishes.
                    refreshVideoSurface()
                    setPointerInside(frame.contains(NSEvent.mouseLocation))
                }
            } else {
                refreshVideoSurface()
                setPointerInside(frame.contains(NSEvent.mouseLocation))
            }
        }
    }

    func dismiss() {
        cancelFrameAnimation()
        NSApp.removeWindowsItem(self)
        orderOut(nil)
        video?.removeFromSuperview()
        video = nil
    }

    func refreshVideoSurface() {
        guard !refreshPending, video != nil else { return }
        refreshPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            refreshPending = false
            guard let video, video.window === self else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layoutContent()
            videoContainer.layoutSubtreeIfNeeded()
            video.setFrameSize(videoContainer.bounds.size)
            video.resize(withOldSuperviewSize: videoContainer.bounds.size)
            video.layer?.setNeedsLayout()
            video.layer?.layoutIfNeeded()
            video.needsDisplay = true
            CATransaction.commit()
        }
    }

    func setSourceSpace(_ space: SpaceModel?) {
        backdrop.rootView = BrowserWindowAtmosphere(space: space)
    }

    private func observeAppearance() {
        let appearance = withObservationTracking {
            BrowserDeviceAppearanceStore.shared.pictureInPictureAppearance
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAppearance() }
        }
        guard appearance != frameAppearance else { return }
        let change = (appearance.borderWidth - borderWidth) * 2
        frameAppearance = appearance
        if change != 0, let visible = screen?.visibleFrame {
            let previous = restingFrame
            let anchor = Self.nearestEdgeAnchor(of: previous, in: visible)
            destination = Self.resized(
                previous, to: previous.width + change, in: visible,
                horizontal: anchor.horizontal, vertical: anchor.vertical,
                borderWidth: borderWidth, aspect: aspect, backingScale: backingScaleFactor)
            retargetOrApplyDestination()
        }
        layoutContent()
        invalidateShadow()
        if change != 0 { refreshVideoSurface() }
    }

    private func layoutContent() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bounds = surface.bounds
        surface.layer?.cornerRadius = frameAppearance.cornerRadius
        let showsBackdrop = borderWidth > 0
        backdrop.isHidden = !showsBackdrop
        if showsBackdrop, backdrop.frame != bounds {
            backdrop.frame = bounds
        }
        let videoFrame = bounds.insetBy(dx: borderWidth, dy: borderWidth)
        if videoContainer.frame != videoFrame {
            videoContainer.frame = videoFrame
        }
        videoContainer.layer?.cornerRadius = frameAppearance.videoCornerRadius
        if let video, video.superview === videoContainer, video.frame != videoContainer.bounds {
            video.frame = videoContainer.bounds
        }
        if let controls {
            let controlsSize = controls.frame.size
            let nextOrigin = NSPoint(
                x: round((bounds.width - controlsSize.width) / 2),
                y: round(bounds.height - controlsSize.height - Self.inset - borderWidth)
            )
            if controls.frame.origin != nextOrigin {
                controls.setFrameOrigin(nextOrigin)
            }
        }
        CATransaction.commit()
    }

    func setVideoSize(_ size: CGSize) {
        let next = Self.aspect(of: size)
        guard next != aspect else { return }
        aspect = next
        guard drag == nil else {
            pendingAspectReconcile = true
            return
        }
        pendingAspectReconcile = false
        if let visible = screen?.visibleFrame {
            let previous = restingFrame
            let anchor = Self.nearestEdgeAnchor(of: previous, in: visible)
            destination = Self.resized(
                previous, to: previous.width, in: visible,
                horizontal: anchor.horizontal, vertical: anchor.vertical,
                borderWidth: borderWidth, aspect: aspect, backingScale: backingScaleFactor)
            retargetOrApplyDestination()
        }
    }

    private func retargetOrApplyDestination() {
        if let active = frameAnimation {
            let remaining = max(0.08, active.duration - (CACurrentMediaTime() - active.startTime))
            frameAnimation = FrameAnimation(
                from: frame,
                to: destination,
                startTime: CACurrentMediaTime(),
                duration: remaining,
                completion: active.completion
            )
        } else if !isPresenting {
            applyFrameWithoutActions(destination)
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
            settings: { [weak self] in self?.onSettings() },
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

    private func updateControlVisibility(animated: Bool = true) {
        let shouldShow = drag?.resizes != true && (pointerIsInside || isKeyWindow)
        guard shouldShow != controlsVisible, let controls else { return }
        controlsVisible = shouldShow
        let targetAlpha: CGFloat = shouldShow ? 1 : 0
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.controlsFadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                controls.animator().alphaValue = targetAlpha
            }
        } else {
            controls.alphaValue = targetAlpha
        }
    }

    // MARK: - Actions - Frame Animation

    private func applyFrameWithoutActions(_ rect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        setFrame(rect, display: true)
        layoutContent()
        CATransaction.commit()
    }

    private func animateFrame(
        to target: CGRect, duration: CFTimeInterval, completion: @escaping @MainActor () -> Void = {}
    ) {
        cancelFrameAnimation()
        destination = target
        let start = frame
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reducesMotion || duration <= 0 || Self.framesNearlyEqual(start, target) {
            applyFrameWithoutActions(target)
            completion()
            return
        }
        frameAnimation = FrameAnimation(
            from: start, to: target, startTime: CACurrentMediaTime(), duration: duration, completion: completion)
        let proxy = DisplayLinkTarget(window: self)
        let link = displayLink(target: proxy, selector: #selector(DisplayLinkTarget.step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stepFrameAnimation(_ link: CADisplayLink) {
        guard let animation = frameAnimation else {
            cancelFrameAnimation()
            return
        }
        let elapsed = CACurrentMediaTime() - animation.startTime
        let progress = min(max(elapsed / animation.duration, 0), 1)
        // Smooth ease-out quartic curve: snappy start, silky 120 Hz deceleration,
        // and no overshoot past display edges.
        let eased = 1 - pow(1 - progress, 4)
        let current = CGRect(
            x: animation.from.minX + (animation.to.minX - animation.from.minX) * eased,
            y: animation.from.minY + (animation.to.minY - animation.from.minY) * eased,
            width: animation.from.width + (animation.to.width - animation.from.width) * eased,
            height: animation.from.height + (animation.to.height - animation.from.height) * eased
        )
        applyFrameWithoutActions(current)
        if progress >= 1 {
            let completion = animation.completion
            cancelFrameAnimation()
            completion()
        }
    }

    private func cancelFrameAnimation() {
        displayLink?.invalidate()
        displayLink = nil
        frameAnimation = nil
        isPresenting = false
    }

    // MARK: - Actions - Pointer

    private func resizeEdges(at point: CGPoint) -> (horizontal: CGFloat, vertical: CGFloat) {
        let margin = max(Self.resizeMargin, borderWidth)
        let horizontal: CGFloat = point.x <= margin ? -1 : point.x >= surface.bounds.width - margin ? 1 : 0
        let vertical: CGFloat = point.y <= margin ? -1 : point.y >= surface.bounds.height - margin ? 1 : 0
        return (horizontal, vertical)
    }

    private func resizeCursor(at point: CGPoint) -> NSCursor {
        let (horizontal, vertical) = resizeEdges(at: point)
        let position: NSCursor.FrameResizePosition
        switch (horizontal, vertical) {
        case (-1, -1): position = .bottomLeft
        case (-1, 1): position = .topLeft
        case (1, -1): position = .bottomRight
        case (1, 1): position = .topRight
        case (-1, _): position = .left
        case (1, _): position = .right
        case (_, -1): position = .bottom
        case (_, 1): position = .top
        default: return .arrow
        }
        return .frameResize(position: position, directions: .all)
    }

    private func beginDrag(at point: CGPoint, time: TimeInterval) {
        cancelFrameAnimation()
        let edges = resizeEdges(at: point)
        let start = NSEvent.mouseLocation
        let visibleFrame =
            screen?.visibleFrame
            ?? NSScreen.screens.first { $0.frame.contains(start) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? frame
        drag = Drag(
            original: frame, visibleFrame: visibleFrame, start: start,
            horizontalEdge: edges.horizontal, verticalEdge: edges.vertical,
            samples: [PointerSample(location: start, time: time)])
        if edges.horizontal != 0 || edges.vertical != 0 {
            updateControlVisibility()
        }
    }

    private func moveDrag(at time: TimeInterval) {
        guard var drag else { return }
        let mouse = NSEvent.mouseLocation
        drag.record(PointerSample(location: mouse, time: time))
        self.drag = drag
        let dx = mouse.x - drag.start.x
        let dy = mouse.y - drag.start.y
        if drag.resizes {
            let delta = Self.resizeWidthDelta(
                dx: dx, dy: dy, horizontalEdge: drag.horizontalEdge, verticalEdge: drag.verticalEdge, aspect: aspect)
            let rect = Self.resized(
                drag.original, to: drag.original.width + delta, in: drag.visibleFrame,
                horizontal: drag.horizontalEdge, vertical: drag.verticalEdge,
                borderWidth: borderWidth, aspect: aspect, backingScale: backingScaleFactor)
            if rect != frame {
                applyFrameWithoutActions(rect)
            }
        } else {
            setFrameOrigin(CGPoint(x: drag.original.minX + dx, y: drag.original.minY + dy))
        }
    }

    private func endDrag(at time: TimeInterval) {
        guard let drag else { return }
        self.drag = nil
        let mouse = NSEvent.mouseLocation
        defer {
            let local = surface.convert(convertPoint(fromScreen: mouse), from: nil)
            (frame.contains(mouse) ? resizeCursor(at: local) : .arrow).set()
            updateControlVisibility()
        }
        if drag.resizes {
            if pendingAspectReconcile {
                pendingAspectReconcile = false
                let reconciled = Self.resized(
                    frame, to: frame.width, in: drag.visibleFrame,
                    horizontal: drag.horizontalEdge, vertical: drag.verticalEdge,
                    borderWidth: borderWidth, aspect: aspect, backingScale: backingScaleFactor)
                destination = reconciled
                if reconciled != frame { applyFrameWithoutActions(reconciled) }
            } else {
                // Live resize already keeps the frame aspect-locked, pixel-aligned,
                // and clamped to its anchored edges; leave it exactly where released.
                destination = frame
            }
            refreshVideoSurface()
            return
        }
        pendingAspectReconcile = false
        guard let visible = (NSScreen.screens.first { $0.frame.contains(mouse) } ?? screen)?.visibleFrame else {
            return
        }
        let dropped = drag.original.offsetBy(dx: mouse.x - drag.start.x, dy: mouse.y - drag.start.y)
        let settled = Self.resized(
            dropped, to: dropped.width, in: visible,
            borderWidth: borderWidth, aspect: aspect, backingScale: backingScaleFactor)
        guard let velocity = drag.flick(at: PointerSample(location: mouse, time: time)) else {
            if Self.framesNearlyEqual(frame, settled) {
                destination = settled
                if frame != settled { applyFrameWithoutActions(settled) }
                refreshVideoSurface()
            } else {
                animateFrame(to: settled, duration: Self.settleDuration) { [weak self] in
                    self?.refreshVideoSurface()
                }
            }
            return
        }
        let horizontal = abs(velocity.dx) >= abs(velocity.dy) * 0.25 ? velocity.dx > 0 : settled.midX > visible.midX
        let vertical = abs(velocity.dy) >= abs(velocity.dx) * 0.25 ? velocity.dy > 0 : settled.midY > visible.midY
        let x = horizontal ? visible.maxX - settled.width - Self.inset : visible.minX + Self.inset
        let y = vertical ? visible.maxY - settled.height - Self.inset : visible.minY + Self.inset
        let target = Self.contained(CGRect(origin: CGPoint(x: x, y: y), size: settled.size), in: visible)
        animateFrame(to: target, duration: Self.flyDuration) { [weak self] in
            self?.refreshVideoSurface()
        }
    }

    // MARK: - Actions - Geometry

    /// Projects a pointer delta onto the dragged edge or corner's aspect-locked
    /// ray so corner resizing is continuous everywhere without sign-flip jumps.
    static func resizeWidthDelta(
        dx: CGFloat, dy: CGFloat, horizontalEdge: CGFloat, verticalEdge: CGFloat, aspect: CGFloat
    ) -> CGFloat {
        if verticalEdge == 0 {
            return dx * horizontalEdge
        }
        if horizontalEdge == 0 {
            return dy * verticalEdge * aspect
        }
        let horizontal = dx * horizontalEdge
        let vertical = dy * verticalEdge * aspect
        let aspectSquared = aspect * aspect
        return (aspectSquared * horizontal + vertical) / (aspectSquared + 1)
    }

    /// Resizes `frame` to `width` while preserving the video's aspect ratio and
    /// keeping any anchored edge or corner pinned inside `bounds`, so hitting a
    /// display edge stops growth cleanly instead of pushing the window back in.
    static func resized(
        _ frame: CGRect, to width: CGFloat, in bounds: CGRect,
        horizontal: CGFloat = 0, vertical: CGFloat = 0,
        borderWidth: CGFloat, aspect: CGFloat, backingScale: CGFloat = 1
    ) -> CGRect {
        let scale = max(1, backingScale)
        let border = borderWidth * 2
        let availableWidth: CGFloat =
            if horizontal < 0 {
                min(bounds.width, max(0, min(frame.maxX, bounds.maxX) - bounds.minX))
            } else if horizontal > 0 {
                min(bounds.width, max(0, bounds.maxX - max(frame.minX, bounds.minX)))
            } else {
                bounds.width
            }
        let availableHeight: CGFloat =
            if vertical < 0 {
                min(bounds.height, max(0, min(frame.maxY, bounds.maxY) - bounds.minY))
            } else if vertical > 0 {
                min(bounds.height, max(0, bounds.maxY - max(frame.minY, bounds.minY)))
            } else {
                bounds.height
            }

        let screenMaximum = min(bounds.width, (bounds.height - border) * aspect + border)
        let anchoredMaximum = min(availableWidth, (availableHeight - border) * aspect + border)
        let maximum = max(border + 1, min(screenMaximum, anchoredMaximum))
        let minimum = min(Self.minimumWidth, maximum)

        let rawWidth = min(max(minimum, width), maximum)
        let alignedWidth: CGFloat
        if rawWidth >= maximum {
            alignedWidth = max(minimum, floor(maximum * scale) / scale)
        } else if rawWidth <= minimum {
            alignedWidth = ceil(minimum * scale) / scale
        } else {
            alignedWidth = round(rawWidth * scale) / scale
        }
        let w = min(max(minimum, alignedWidth), maximum)
        let rawHeight = (w - border) / aspect + border
        let h = min(availableHeight, max(1, floor(rawHeight * scale + 0.5) / scale))

        let x: CGFloat =
            if horizontal < 0 {
                frame.maxX - w
            } else if horizontal > 0 {
                frame.minX
            } else {
                round((frame.midX - w / 2) * scale) / scale
            }
        let y: CGFloat =
            if vertical < 0 {
                frame.maxY - h
            } else if vertical > 0 {
                frame.minY
            } else {
                round((frame.midY - h / 2) * scale) / scale
            }
        return Self.contained(CGRect(x: x, y: y, width: w, height: h), in: bounds)
    }

    private static func nearestEdgeAnchor(of frame: CGRect, in bounds: CGRect) -> (
        horizontal: CGFloat, vertical: CGFloat
    ) {
        let threshold = Self.inset * 2
        let horizontal: CGFloat =
            if abs(bounds.maxX - frame.maxX) <= threshold {
                -1
            } else if abs(frame.minX - bounds.minX) <= threshold {
                1
            } else {
                0
            }
        let vertical: CGFloat =
            if abs(bounds.maxY - frame.maxY) <= threshold {
                -1
            } else if abs(frame.minY - bounds.minY) <= threshold {
                1
            } else {
                0
            }
        return (horizontal, vertical)
    }

    private static func framesNearlyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5
            && abs(a.minY - b.minY) < 0.5
            && abs(a.width - b.width) < 0.5
            && abs(a.height - b.height) < 0.5
    }

    static func contained(_ rect: CGRect, in bounds: CGRect) -> CGRect {
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
