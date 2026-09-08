import AppKit
import QuartzCore
import SwiftUI

/// Retains native page roots and moves their existing layers without publishing
/// gesture progress into the SwiftUI trees those roots contain.
@MainActor
final class SpacePagerViewport<Content: View>: NSView {
    struct Motion {
        let generation: UInt
        let origin: BrowserSpaceRuntimeAssignment
        var target: BrowserSpaceRuntimeAssignment?
        var amount: CGFloat = 0
        var gestureSucceeded = false
        let commitsSelection: Bool
        let usesNativeTracking: Bool
    }

    private(set) var spaces: [BrowserSpace] = []
    private(set) var selectedSpaceID: SpaceID?
    private(set) var presentationSpaceID: SpaceID?
    private(set) var isInteractionLocked = false
    private(set) var reduceMotion = false
    private(set) var layoutDirection = LayoutDirection.leftToRight
    private(set) var motion: Motion?
    private var generation: UInt = 0
    private var expectedSelection: SpaceID?
    private var hosts: [BrowserSpaceRuntimeAssignment: SpacePageHost<Content>] = [:]
    private var makeRoot: ((BrowserSpace, Bool) -> SpacePageRoot<Content>)?
    private var selectSpace: (SpaceID) -> SpaceID = { $0 }
    private var settledSpace: (SpaceID) -> Void = { _ in }
    private var lastSize = CGSize.zero
    private lazy var gesture = SpacePagerGesture(viewport: self)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func update(
        spaces: [BrowserSpace], selectedSpaceID: SpaceID,
        isInteractionLocked: Bool, reduceMotion: Bool, layoutDirection: LayoutDirection,
        selectSpace: @escaping (SpaceID) -> SpaceID, settledSpace: @escaping (SpaceID) -> Void,
        makeRoot: @escaping (BrowserSpace, Bool) -> SpacePageRoot<Content>
    ) {
        let assignmentsChanged =
            self.spaces.map(BrowserSpaceRuntimeAssignment.init(space:))
            != spaces.map(BrowserSpaceRuntimeAssignment.init(space:))
        let selectionChanged = self.selectedSpaceID != selectedSpaceID
        let invalidatesMotion =
            assignmentsChanged || isInteractionLocked
            || self.reduceMotion != reduceMotion || self.layoutDirection != layoutDirection
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.isInteractionLocked = isInteractionLocked
        self.reduceMotion = reduceMotion
        self.layoutDirection = layoutDirection
        self.selectSpace = selectSpace
        self.settledSpace = settledSpace
        self.makeRoot = makeRoot

        if invalidatesMotion {
            cancelMotion()
            gesture.cancelCurrentGesture()
            presentationSpaceID = selectedSpaceID
            expectedSelection = nil
        } else if selectionChanged {
            if expectedSelection == selectedSpaceID {
                expectedSelection = nil
                presentationSpaceID = selectedSpaceID
            } else {
                // An actual authoritative selection change supersedes native
                // tracking; unrelated updates carrying the old ID do not.
                cancelMotion()
                gesture.cancelCurrentGesture()
                if let origin = presentationSpaceID, origin != selectedSpaceID, !reduceMotion {
                    prepareHosts(around: selectedSpaceID, retaining: origin)
                    animate(to: selectedSpaceID, commitsSelection: false)
                    return
                }
                presentationSpaceID = selectedSpaceID
            }
        }
        guard motion == nil else {
            updateAccessibility()
            return
        }
        if presentationSpaceID == nil { presentationSpaceID = selectedSpaceID }
        prepareHosts(around: presentationSpaceID ?? selectedSpaceID)
        positionHosts()
        updateAccessibility()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        gesture.attach(to: window)
        if window == nil { cancelMotion() }
    }

    override func layout() {
        super.layout()
        if lastSize != bounds.size {
            lastSize = bounds.size
            if motion != nil {
                cancelMotion()
                presentationSpaceID = selectedSpaceID
            }
        }
        for host in hosts.values { host.frame = bounds }
        if motion == nil { positionHosts() }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), !isHiddenOrHasHiddenAncestor else { return nil }
        // Layer translations intentionally do not rewrite row geometry during
        // motion. No control or drag target can use that resting geometry then.
        guard motion == nil, expectedSelection == nil,
            let selectedSpaceID, let key = assignment(for: selectedSpaceID)
        else { return self }
        return hosts[key]?.hitTest(local) ?? self
    }

    func teardown() {
        gesture.attach(to: nil)
        cancelMotion()
        for host in hosts.values { host.removeFromSuperview() }
        hosts.removeAll()
        makeRoot = nil
    }

    func neighbor(forPhysicalDirection direction: CGFloat) -> BrowserSpaceRuntimeAssignment? {
        guard let presentationSpaceID else { return nil }
        let forward = layoutDirection == .leftToRight ? direction < 0 : direction > 0
        guard
            let id = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: presentationSpaceID, direction: forward ? .next : .previous)
        else { return nil }
        return assignment(for: id)
    }

    func beginInteractiveMotion() -> UInt? {
        guard !isInteractionLocked, bounds.width > 0, spaces.count > 1 else { return nil }
        interruptForNewGesture()
        guard let presentationSpaceID, let origin = assignment(for: presentationSpaceID) else { return nil }
        prepareHosts(around: presentationSpaceID, refreshContent: false)
        generation &+= 1
        motion = Motion(generation: generation, origin: origin, commitsSelection: true, usesNativeTracking: true)
        positionHosts()
        updateAccessibility()
        return generation
    }

    func updateInteractiveMotion(_ amount: CGFloat, phase: NSEvent.Phase, token: UInt, complete: Bool) -> Bool {
        guard var current = motion, current.generation == token,
            !isInteractionLocked, !isHiddenOrHasHiddenAncestor, window != nil
        else { return false }
        current.amount = amount
        if amount != 0 { current.target = neighbor(forPhysicalDirection: amount) }
        if phase.contains(.ended) { current.gestureSucceeded = current.target != nil }
        if phase.contains(.cancelled) { current.gestureSucceeded = false }
        motion = current
        positionHosts()
        if complete {
            finishMotion(
                token: token, destination: abs(amount) > 0.5 ? current.target?.spaceID : current.origin.spaceID)
        }
        return true
    }

    func step(_ direction: BrowserSpaceSwipeDirection) {
        guard !isInteractionLocked else { return }
        interruptForNewGesture()
        guard let presentationSpaceID,
            let next = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: presentationSpaceID, direction: direction == .next ? .next : .previous)
        else { return }
        prepareHosts(around: presentationSpaceID, retaining: next, refreshContent: false)
        animate(to: next, commitsSelection: true)
    }

    func interruptForNewGesture() {
        guard let current = motion else { return }
        // A second physical gesture continues from a successful first one,
        // without waiting for its settle callback or publishing selection early.
        let destination = current.gestureSucceeded ? current.target?.spaceID : nil
        cancelMotion()
        presentationSpaceID = destination ?? current.origin.spaceID
        positionHosts()
        updateAccessibility()
    }

    func cancelMotion() {
        generation &+= 1
        motion = nil
        for host in hosts.values { host.layer?.removeAnimation(forKey: "space-motion") }
        positionHosts()
        updateAccessibility()
    }

    private func animate(to destination: SpaceID, commitsSelection: Bool) {
        guard let presentationSpaceID, let origin = assignment(for: presentationSpaceID),
            let target = assignment(for: destination)
        else { return }
        generation &+= 1
        let token = generation
        let originIndex = spaces.firstIndex { $0.id == origin.spaceID } ?? 0
        let targetIndex = spaces.firstIndex { $0.id == target.spaceID } ?? originIndex
        let logicalDirection: CGFloat = targetIndex > originIndex ? -1 : 1
        let amount = logicalDirection * (layoutDirection == .leftToRight ? 1 : -1)
        motion = Motion(
            generation: token, origin: origin, target: target, gestureSucceeded: true,
            commitsSelection: commitsSelection, usesNativeTracking: false)
        // Direct jumps use the same one-width presentation as adjacent steps.
        positionHosts(targetOverride: target)
        updateAccessibility()
        if reduceMotion {
            finishMotion(token: token, destination: destination)
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            Task { @MainActor in self?.finishMotion(token: token, destination: destination) }
        }
        for (key, host) in hosts {
            guard let layer = host.layer else { continue }
            let start = layer.affineTransform().tx
            let end = start + amount * bounds.width
            layer.setAffineTransform(CGAffineTransform(translationX: end, y: 0))
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = start
            animation.toValue = end
            animation.duration = 0.22
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            if key == origin || key == target { layer.add(animation, forKey: "space-motion") }
        }
        CATransaction.commit()
    }

    private func finishMotion(token: UInt, destination: SpaceID?) {
        guard let current = motion, current.generation == token,
            assignment(for: current.origin.spaceID) == current.origin,
            let destination, assignment(for: destination) != nil
        else { return }
        motion = nil
        presentationSpaceID = destination
        if current.commitsSelection, destination != selectedSpaceID { expectedSelection = destination }
        positionHosts()
        updateAccessibility()
        if current.commitsSelection, destination != selectedSpaceID {
            let actual = selectSpace(destination)
            if actual != destination {
                expectedSelection = nil
                selectedSpaceID = actual
                presentationSpaceID = actual
                prepareHosts(around: actual)
                positionHosts()
                updateAccessibility()
                settledSpace(actual)
                return
            }
        }
        settledSpace(destination)
        // Model updates refresh content after visual completion, never once
        // per progress sample. Cancellation may finish without a model update.
        if expectedSelection == nil {
            prepareHosts(around: destination)
            positionHosts()
            updateAccessibility()
        }
    }

    private func assignment(for id: SpaceID) -> BrowserSpaceRuntimeAssignment? {
        spaces.first { $0.id == id }.map(BrowserSpaceRuntimeAssignment.init(space:))
    }

    private func prepareHosts(around id: SpaceID, retaining extra: SpaceID? = nil, refreshContent: Bool = true) {
        guard let makeRoot, let index = spaces.firstIndex(where: { $0.id == id }) else { return }
        let neighbors = spaces[max(0, index - 1)...min(spaces.count - 1, index + 1)]
        var required = Set(neighbors.map { BrowserSpaceRuntimeAssignment(space: $0) })
        if let extra, let key = assignment(for: extra) { required.insert(key) }
        let spare = spaces.enumerated().filter {
            let key = BrowserSpaceRuntimeAssignment(space: $0.element)
            return hosts[key] != nil && !required.contains(key)
        }.sorted { abs($0.offset - index) < abs($1.offset - index) }
            .prefix(max(0, 4 - required.count))
        required.formUnion(spare.map { BrowserSpaceRuntimeAssignment(space: $0.element) })
        for key in hosts.keys where !required.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for space in spaces {
            let key = BrowserSpaceRuntimeAssignment(space: space)
            guard required.contains(key) else { continue }
            if let host = hosts[key] {
                if refreshContent { host.hostingView.rootView = makeRoot(space, space.id == selectedSpaceID) }
            } else {
                let host = SpacePageHost(root: makeRoot(space, space.id == selectedSpaceID))
                host.frame = bounds
                host.hostingView.frame = host.bounds
                hosts[key] = host
                addSubview(host)
            }
        }
    }

    private func positionHosts(targetOverride: BrowserSpaceRuntimeAssignment? = nil) {
        guard let presentationSpaceID,
            let origin = spaces.firstIndex(where: { $0.id == presentationSpaceID })
        else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (key, host) in hosts {
            guard let index = spaces.firstIndex(where: { $0.id == key.spaceID }) else { continue }
            var distance = CGFloat(index - origin)
            if targetOverride == key { distance = distance < 0 ? -1 : 1 }
            let offset = distance * (layoutDirection == .leftToRight ? 1 : -1) + (motion?.amount ?? 0)
            host.layer?.setAffineTransform(CGAffineTransform(translationX: offset * bounds.width, y: 0))
        }
        CATransaction.commit()
    }

    private func updateAccessibility() {
        let hasPresentation = presentationSpaceID.flatMap { assignment(for: $0) } != nil
        for (key, host) in hosts {
            // A direct jump compresses its destination into one page width.
            // Other retained pages must not appear beneath that transition.
            let participates =
                motion.map {
                    $0.usesNativeTracking || key == $0.origin || key == $0.target
                } ?? true
            host.layer?.opacity = hasPresentation && participates ? 1 : 0
            host.setAccessibilityHidden(key.spaceID != selectedSpaceID || motion != nil || expectedSelection != nil)
        }
    }
}
