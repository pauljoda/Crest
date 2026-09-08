import AppKit
import QuartzCore
import SwiftUI

/// Retains native page roots and moves their actual views without publishing
/// gesture progress into the SwiftUI trees those roots contain.
@MainActor
final class SpacePagerViewport<Content: View>: NSView {
    struct Motion {
        let generation: UInt
        let origin: BrowserSpaceRuntimeAssignment
        var target: BrowserSpaceRuntimeAssignment?
        var offset: CGFloat = 0
        var initialRawOffset: CGFloat = 0
        var resistanceLength: CGFloat = 0
        var translation: CGFloat = 0
        var direction: CGFloat = 0
        var settledDestination: SpaceID?
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
    private var presentation: SpacePagerPresentation?
    private var motionDisplayLink: CADisplayLink?
    private lazy var frameObserver = SpacePagerFrameObserver { [weak self] in
        self?.publishPresentation(sampleAnimated: true)
    }
    private lazy var gesture = SpacePagerGesture(viewport: self)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { return nil }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    var gestureBounds: CGRect {
        let inset = max(0, presentation?.gestureTopInset ?? 0)
        return CGRect(x: bounds.minX, y: bounds.minY - inset, width: bounds.width, height: bounds.height + inset)
    }

    func update(
        spaces: [BrowserSpace], selectedSpaceID: SpaceID,
        isInteractionLocked: Bool, reduceMotion: Bool, layoutDirection: LayoutDirection,
        presentation: SpacePagerPresentation? = nil,
        selectSpace: @escaping (SpaceID) -> SpaceID, settledSpace: @escaping (SpaceID) -> Void,
        makeRoot: @escaping (BrowserSpace, Bool) -> SpacePageRoot<Content>
    ) {
        let assignmentsChanged =
            self.spaces.map(BrowserSpaceRuntimeAssignment.init(space:))
            != spaces.map(BrowserSpaceRuntimeAssignment.init(space:))
        let selectionChanged = self.selectedSpaceID != selectedSpaceID
        let accessPoliciesChanged = self.spaces.map(\.accessPolicy) != spaces.map(\.accessPolicy)
        let invalidatesMotion =
            assignmentsChanged || accessPoliciesChanged || isInteractionLocked
            || self.reduceMotion != reduceMotion || self.layoutDirection != layoutDirection
        self.presentation = presentation
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
        } else if expectedSelection == selectedSpaceID {
            // A rapid accepted return can equal the old local ID. Its receipt
            // must be acknowledged even without a selectionChanged edge.
            expectedSelection = nil
            if motion == nil { presentationSpaceID = selectedSpaceID }
        } else if selectionChanged {
            // Actual authoritative selection changes supersede native motion;
            // unrelated updates carrying the old ID do not.
            expectedSelection = nil
            cancelMotion()
            gesture.cancelCurrentGesture()
            if let origin = presentationSpaceID, !reduceMotion,
                let originIndex = spaces.firstIndex(where: { $0.id == origin }),
                let targetIndex = spaces.firstIndex(where: { $0.id == selectedSpaceID }),
                abs(targetIndex - originIndex) == 1
            {
                // Retained pages keep their visible content until the slide
                // finishes. The latest roots are supplied at completion.
                prepareHosts(around: selectedSpaceID, retaining: origin, refreshContent: false)
                animate(to: selectedSpaceID, commitsSelection: false)
                return
            }
            // A direct nonadjacent choice presents its authoritative page.
            // It does not create a compressed strip of unrelated neighbors.
            presentationSpaceID = selectedSpaceID
        }
        guard motion == nil else {
            updateAccessibility()
            publishPresentation(sampleAnimated: true)
            return
        }
        if presentationSpaceID == nil { presentationSpaceID = selectedSpaceID }
        prepareHosts(around: presentationSpaceID ?? selectedSpaceID)
        positionHosts()
        updateAccessibility()
        publishPresentation()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        gesture.attach(to: window)
        if window == nil {
            presentationSpaceID = expectedSelection ?? selectedSpaceID
            cancelMotion()
            publishPresentation()
        } else if motion == nil, let presentationSpaceID {
            // Detachment can cancel a slide before its deferred root refresh.
            prepareHosts(around: presentationSpaceID)
            positionHosts()
            updateAccessibility()
            publishPresentation()
        }
    }

    override func layout() {
        super.layout()
        if lastSize != bounds.size {
            lastSize = bounds.size
            if motion != nil {
                cancelMotion()
                presentationSpaceID = selectedSpaceID
                if let presentationSpaceID {
                    prepareHosts(around: presentationSpaceID)
                    updateAccessibility()
                }
            }
        }
        for host in hosts.values where host.frame.size != bounds.size { host.setFrameSize(bounds.size) }
        if motion == nil {
            positionHosts()
            publishPresentation()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), !isHiddenOrHasHiddenAncestor else { return nil }
        // During settling AppKit's model frames already describe the endpoint.
        // Controls become available when their visible frames have arrived.
        guard motion == nil, expectedSelection == nil,
            let selectedSpaceID, let key = assignment(for: selectedSpaceID)
        else { return self }
        return hosts[key]?.hitTest(local) ?? self
    }

    func teardown() {
        gesture.attach(to: nil)
        presentationSpaceID = expectedSelection ?? selectedSpaceID
        cancelMotion()
        publishPresentation()
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
        stopPresentationSampling()
        let previous = motion
        let originID = previous?.origin.spaceID ?? presentationSpaceID
        guard let originID, var origin = assignment(for: originID), hosts[origin] != nil else { return nil }
        var inheritedOffset = previous.map { visibleOffset(for: origin, during: $0) } ?? 0
        if previous != nil, let index = spaces.firstIndex(where: { $0.id == origin.spaceID }) {
            // Restart from the nearest visible page, using one presentation
            // sample for the entire strip. A newly admitted neighbor's layer
            // can still report geometry from an earlier layout transaction.
            let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
            let displacement = Int((-inheritedOffset * direction / bounds.width).rounded())
            let nearestIndex = min(spaces.count - 1, max(0, index + displacement))
            let nearest = BrowserSpaceRuntimeAssignment(space: spaces[nearestIndex])
            if hosts[nearest] != nil {
                inheritedOffset += CGFloat(nearestIndex - index) * bounds.width * direction
                origin = nearest
            }
        }
        generation &+= 1
        // Capture presentation before removing an interrupted spring. The new
        // gesture owns its displacement independently of this inherited offset.
        stopHostAnimations()
        presentationSpaceID = origin.spaceID
        let minimum: CGFloat = neighbor(forPhysicalDirection: -1) == nil ? 0 : -bounds.width
        let maximum: CGFloat = neighbor(forPhysicalDirection: 1) == nil ? 0 : bounds.width
        let limit = min(maximum, max(minimum, inheritedOffset))
        let excess = inheritedOffset - limit
        let resistanceLength = max(bounds.width * 0.2, abs(excess) * 2)
        // The captured value has already passed through resistance. Invert it
        // once so the next sample cannot apply that resistance a second time.
        let rawOffset = limit + excess / (1 - abs(excess) / resistanceLength)
        motion = Motion(
            generation: generation, origin: origin, offset: inheritedOffset,
            initialRawOffset: rawOffset, resistanceLength: resistanceLength,
            commitsSelection: true, usesNativeTracking: true)
        positionHosts()
        updateAccessibility()
        publishPresentation()
        return generation
    }

    func updateInteractiveMotion(deltaX: CGFloat, token: UInt) -> Bool {
        guard var current = motion, current.generation == token, current.settledDestination == nil,
            !isInteractionLocked, !isHiddenOrHasHiddenAncestor, window != nil
        else { return false }
        if current.direction == 0, deltaX != 0 {
            current.direction = deltaX < 0 ? -1 : 1
            current.target = neighbor(forPhysicalDirection: current.direction)
            if let target = current.target, hosts[target] == nil {
                // Normal input already has its destination. Only a gesture
                // outrunning the bounded cache needs this particular page.
                prepareHosts(around: current.origin.spaceID, retaining: target.spaceID, refreshContent: false)
            }
        }
        current.translation += deltaX
        let travel = current.direction * max(0, current.translation * current.direction)
        let rawOffset = current.initialRawOffset + travel
        let minimum: CGFloat = neighbor(forPhysicalDirection: -1) == nil ? 0 : -bounds.width
        let maximum: CGFloat = neighbor(forPhysicalDirection: 1) == nil ? 0 : bounds.width
        current.offset = resistedOffset(
            rawOffset, minimum: minimum, maximum: maximum, resistanceLength: current.resistanceLength)
        motion = current
        positionHosts()
        publishPresentation()
        return true
    }

    func endInteractiveMotion(velocity: CGFloat, cancelled: Bool, token: UInt) -> Bool {
        guard let current = motion, current.generation == token, current.settledDestination == nil,
            !isInteractionLocked, !isHiddenOrHasHiddenAncestor, window != nil
        else { return false }
        let travel = max(0, current.translation * current.direction)
        // Include the inherited visible displacement when restarting a swipe.
        // Release chooses where the page is heading, without scaling tracking.
        let visibleVelocity = cancelled ? 0 : visibleVelocity(velocity, during: current)
        let projectedTravel = (current.offset + visibleVelocity * 0.15) * current.direction
        let completes = !cancelled && travel > 0 && projectedTravel >= bounds.width / 2
        let destination = completes ? current.target?.spaceID : nil
        settleMotion(to: destination ?? current.origin.spaceID, velocity: visibleVelocity)
        return true
    }

    func step(_ direction: BrowserSpaceSwipeDirection) {
        guard !isInteractionLocked else { return }
        guard let token = beginInteractiveMotion(), let current = motion,
            let next = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces, selectedSpaceID: current.origin.spaceID,
                direction: direction == .next ? .next : .previous)
        else {
            if let current = motion, current.settledDestination == nil {
                settleMotion(to: current.origin.spaceID, velocity: 0)
            }
            return
        }
        guard motion?.generation == token else { return }
        let physical: CGFloat = (direction == .next ? -1 : 1) * (layoutDirection == .leftToRight ? 1 : -1)
        motion?.direction = physical
        motion?.target = assignment(for: next)
        if let target = motion?.target, hosts[target] == nil {
            prepareHosts(around: current.origin.spaceID, retaining: next, refreshContent: false)
        }
        settleMotion(to: next, velocity: 0)
    }

    func cancelMotion() {
        stopPresentationSampling()
        generation &+= 1
        motion = nil
        stopHostAnimations()
        positionHosts()
        updateAccessibility()
    }

    private func animate(to destination: SpaceID, commitsSelection: Bool) {
        guard let presentationSpaceID, let origin = assignment(for: presentationSpaceID),
            let target = assignment(for: destination)
        else { return }
        generation &+= 1
        let originIndex = spaces.firstIndex { $0.id == origin.spaceID } ?? 0
        let targetIndex = spaces.firstIndex { $0.id == target.spaceID } ?? originIndex
        let direction: CGFloat = (targetIndex > originIndex ? -1 : 1) * (layoutDirection == .leftToRight ? 1 : -1)
        motion = Motion(
            generation: generation, origin: origin, target: target, direction: direction,
            commitsSelection: commitsSelection, usesNativeTracking: false)
        positionHosts()
        updateAccessibility()
        settleMotion(to: destination, velocity: 0)
    }

    private func resistedOffset(
        _ offset: CGFloat, minimum: CGFloat, maximum: CGFloat, resistanceLength: CGFloat
    ) -> CGFloat {
        let limit = min(maximum, max(minimum, offset))
        let excess = offset - limit
        guard excess != 0 else { return offset }
        return limit + excess / (1 + abs(excess) / resistanceLength)
    }

    private func visibleVelocity(_ velocity: CGFloat, during current: Motion) -> CGFloat {
        guard current.translation * current.direction > 0 else { return 0 }
        let rawOffset = current.initialRawOffset + current.translation
        let minimum: CGFloat = neighbor(forPhysicalDirection: -1) == nil ? 0 : -bounds.width
        let maximum: CGFloat = neighbor(forPhysicalDirection: 1) == nil ? 0 : bounds.width
        let excess = rawOffset - min(maximum, max(minimum, rawOffset))
        guard excess != 0 else { return velocity }
        let scale = 1 + abs(excess) / current.resistanceLength
        return velocity / (scale * scale)
    }

    private func visibleOffset(for key: BrowserSpaceRuntimeAssignment, during current: Motion) -> CGFloat {
        guard let host = hosts[key] else { return 0 }
        if current.settledDestination != nil {
            return host.layer?.presentation()?.frame.minX ?? restingOffset(for: key, during: current)
                + current.offset
        }
        return host.frame.minX
    }

    private func settleMotion(to destination: SpaceID, velocity: CGFloat) {
        guard var current = motion, assignment(for: destination) != nil else { return }
        let token = current.generation
        let startOffset = visibleOffset(for: current.origin, during: current)
        current.offset = startOffset
        current.settledDestination = destination
        let targetOffset: CGFloat = destination == current.origin.spaceID ? 0 : current.direction * bounds.width
        let perceptualDuration: TimeInterval = 0.22
        let spring = CASpringAnimation(perceptualDuration: perceptualDuration, bounce: 0)
        let distance = targetOffset - startOffset
        // Core Animation velocity is normalized to signed remaining distance.
        spring.initialVelocity = abs(distance) > 0.01 ? velocity / distance : 0
        spring.duration = spring.settlingDuration
        motion = current
        updateAccessibility()
        publishPresentation()
        guard !reduceMotion, abs(targetOffset - startOffset) > 0.01 else {
            finishMotion(token: token, destination: destination)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = spring.duration
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            for (key, host) in hosts {
                let end = restingOffset(for: key, during: current) + targetOffset
                let pageSpring = CASpringAnimation(perceptualDuration: perceptualDuration, bounce: 0)
                pageSpring.duration = spring.duration
                pageSpring.initialVelocity = spring.initialVelocity
                // The last tracking frame may not have rendered yet. AppKit's
                // default start can then be an older, different offset for each
                // page; give it the coherent native position we just tracked.
                pageSpring.fromValue = NSValue(point: host.frame.origin)
                host.animations = ["frameOrigin": pageSpring]
                host.animator().setFrameOrigin(NSPoint(x: end, y: 0))
            }
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.finishMotion(token: token, destination: destination) }
        }
        startPresentationSampling()
    }

    private func finishMotion(token: UInt, destination: SpaceID?) {
        guard let current = motion, current.generation == token,
            assignment(for: current.origin.spaceID) == current.origin,
            let destination, assignment(for: destination) != nil
        else { return }
        stopPresentationSampling()
        let committedSelection = expectedSelection ?? selectedSpaceID
        motion = nil
        presentationSpaceID = destination
        if current.commitsSelection, destination != committedSelection { expectedSelection = destination }
        stopHostAnimations()
        positionHosts()
        updateAccessibility()
        publishPresentation()
        if current.commitsSelection, destination != committedSelection {
            let actual = selectSpace(destination)
            if actual != destination {
                expectedSelection = nil
                selectedSpaceID = actual
                presentationSpaceID = actual
                prepareHosts(around: actual)
                positionHosts()
                updateAccessibility()
                publishPresentation()
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

    private func publishPresentation(sampleAnimated: Bool = false) {
        guard let presentation, let originID = motion?.origin.spaceID ?? presentationSpaceID,
            let index = spaces.firstIndex(where: { $0.id == originID })
        else { return }
        let offset: CGFloat
        if let motion {
            offset =
                sampleAnimated && motion.settledDestination != nil
                ? visibleOffset(for: motion.origin, during: motion) : motion.offset
        } else {
            offset = 0
        }
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        let position = CGFloat(index) - (bounds.width > 0 ? offset / bounds.width * direction : 0)
        presentation.publish(
            .init(
                generation: generation, spaceIDs: spaces.map(\.id), position: position,
                phase: motion == nil ? .idle : motion?.settledDestination == nil ? .tracking : .settling,
                destinationID: motion?.settledDestination ?? motion?.target?.spaceID ?? originID))
    }

    private func startPresentationSampling() {
        guard presentation != nil, motionDisplayLink == nil, window != nil else { return }
        let link = displayLink(target: frameObserver, selector: #selector(SpacePagerFrameObserver.sample(_:)))
        link.add(to: .main, forMode: .common)
        motionDisplayLink = link
    }

    private func stopPresentationSampling() {
        motionDisplayLink?.invalidate()
        motionDisplayLink = nil
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
                host.frame = CGRect(
                    x: restingOffset(for: key, during: motion) + (motion?.offset ?? 0), y: 0,
                    width: bounds.width, height: bounds.height)
                host.hostingView.frame = host.bounds
                hosts[key] = host
                addSubview(host)
            }
        }
    }

    private func restingOffset(for key: BrowserSpaceRuntimeAssignment, during current: Motion?) -> CGFloat {
        guard let originID = current?.origin.spaceID ?? presentationSpaceID,
            let origin = spaces.firstIndex(where: { $0.id == originID }),
            let index = spaces.firstIndex(where: { $0.id == key.spaceID })
        else { return 0 }
        let distance = CGFloat(index - origin)
        return distance * (layoutDirection == .leftToRight ? 1 : -1) * bounds.width
    }

    private func positionHosts() {
        for (key, host) in hosts {
            let offset = restingOffset(for: key, during: motion) + (motion?.offset ?? 0)
            let origin = NSPoint(x: offset, y: 0)
            if host.frame.origin != origin { host.setFrameOrigin(origin) }
        }
    }

    private func stopHostAnimations() {
        // Only the pager animates these wrapper layers. Removing their motion
        // leaves descendant SwiftUI animations alone. Position is always set
        // through NSView immediately afterward, including interruption rebasing.
        for host in hosts.values { host.layer?.removeAllAnimations() }
    }

    private func updateAccessibility() {
        let hasPresentation = presentationSpaceID.flatMap { assignment(for: $0) } != nil
        for (key, host) in hosts {
            // Programmatic slides display their origin and destination only.
            // Tracking keeps adjacent pages ready in either physical direction.
            let participates =
                motion.map {
                    if $0.usesNativeTracking {
                        return abs(restingOffset(for: key, during: $0)) <= bounds.width
                    }
                    return key == $0.origin || key == $0.target
                } ?? true
            host.isHidden = !hasPresentation || !participates
            host.setAccessibilityHidden(key.spaceID != selectedSpaceID || motion != nil || expectedSelection != nil)
        }
    }
}

/// Keeps the Objective-C display-link target independent of the generic page root.
@MainActor
private final class SpacePagerFrameObserver: NSObject {
    let update: () -> Void

    init(update: @escaping () -> Void) { self.update = update }

    @objc func sample(_ link: CADisplayLink) { update() }
}
