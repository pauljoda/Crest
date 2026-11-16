import AppKit
import QuartzCore
import SwiftUI

/// A passive strip of real content surfaces. Only the sidebar owns gestures;
/// web history gestures continue to belong to WebKit.
///
/// The macOS host of the shared strip: `SpacePageStrip` decides where each
/// page stands, or how opaque it is where pages fade rather than slide, which
/// pages are kept and what each shows; this view hosts the pages and moves
/// them with Core Animation, along the pager's position as a finger moves it
/// and along its release curve as it settles.
@MainActor
final class SpaceContentPagerView<Content: View & Equatable>: NSView {
    /// The order the strip runs along: the pager's, which is every Space in
    /// its order except while a slide jumps to a Space further away.
    private var spaces: [SpaceModel] = []
    /// Every Space in its order.
    private var allSpaces: [SpaceModel] = []
    /// The pinned tab each Space shows, for the Spaces that show one.
    private var shownPins: [UUID: UUID] = [:]
    private var selectedSpaceID: UUID?
    private var lockedSpaceIDs: Set<UUID> = []
    /// Where each page of `spaces` stands and what it shows.
    private var strip = SpacePageStrip([], shownPins: [:])
    private var layoutDirection = LayoutDirection.leftToRight
    private var presentation: SpacePagerPresentation?
    private var snapshot: SpacePagerPresentation.Snapshot?
    private var transition: SpacePagerSettlement?
    private var hosts: [BrowserSpaceRuntimeAssignment: SpacePageHost<Content>] = [:]
    private var makeRoot: ((SpaceModel, Bool) -> SpacePageRoot<Content>)?
    private var lastSize = CGSize.zero
    private var preparedDestination: UUID?
    /// Whether the pages slide with the pager, or keep their place and fade.
    private var slides = true
    /// The Space the strip last came to rest on, which a fade leaves.
    private var restingSpaceID: UUID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        clipsToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    /// Shows `spaces`, where `shownPins` is the pinned tab each Space shows,
    /// for the Spaces that show one. The pages slide with `presentation`'s
    /// pager when `slides`, and fade from one to the next with it otherwise.
    func update(
        spaces: [SpaceModel], selectedSpaceID: UUID, lockedSpaceIDs: Set<UUID>, shownPins: [UUID: UUID],
        layoutDirection: LayoutDirection, presentation: SpacePagerPresentation?, slides: Bool,
        makeRoot: @escaping (SpaceModel, Bool) -> SpacePageRoot<Content>
    ) {
        let changedLocks = self.lockedSpaceIDs.symmetricDifference(lockedSpaceIDs)
        // A Space that joins or leaves a group keeps its page, which takes a
        // root for the new profile below.
        hosts.follow(spaces.filter { !changedLocks.contains($0.id) })
        let assignments = Set(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        // Withdraw old clear surfaces before admitting roots for a new lock.
        // In-flight reversal cannot resurrect those hosts.
        for key in hosts.keys where changedLocks.contains(key.spaceID) || !assignments.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        allSpaces = spaces
        self.shownPins = shownPins
        self.selectedSpaceID = selectedSpaceID
        self.lockedSpaceIDs = lockedSpaceIDs
        self.layoutDirection = layoutDirection
        self.makeRoot = makeRoot
        if self.slides != slides {
            stopAnimations()
            self.slides = slides
        }
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
            presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        }
        let current = matchingSnapshot ?? restingSnapshot(selectedSpaceID)
        arrange(current.order(of: allSpaces) ?? allSpaces)
        if jumps(from: snapshot, to: current) { dissolve() }
        snapshot = current
        if current.phase == .idle { restingSpaceID = current.destinationID }
        prepareHosts(
            at: current.position, destination: current.destinationID, refresh: current.phase == .idle,
            preparesNeighbors: current.phase == .idle)
        if transition == nil { positionHosts(at: current.position) }
        updateAccessibility()
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        transition = nil
        for host in hosts.values { host.layer?.removeAllAnimations() }
    }

    override func layout() {
        super.layout()
        guard lastSize != bounds.size else { return }
        lastSize = bounds.size
        // A sidebar animation resizes this viewport on every frame. A slide
        // already running keeps going: its pages are re-aimed at the new size
        // from the moment it began, rather than restarting it every frame.
        let moving = transition == nil ? [] : slidingHosts
        let began = transition == nil ? nil : slideBeginTime
        for host in hosts.values {
            // A fade keeps going: the pages it fades stay where they are.
            if slides { host.layer?.removeAllAnimations() }
            // Keep offscreen pages cached without reflowing their native content.
            if host.hostingView.rootView.contentPresentation != .inactive, host.frame.size != bounds.size {
                host.setFrameSize(bounds.size)
            }
        }
        if let snapshot {
            prepareHosts(
                at: snapshot.position, destination: snapshot.destinationID, refresh: false,
                preparesNeighbors: snapshot.phase == .idle)
            positionHosts(at: snapshot.position)
        }
        if let transition, slides { resumeSlide(moving, along: transition, beganAt: began) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)),
            snapshot?.phase == .idle, snapshot?.destinationID == selectedSpaceID
        else { return nil }
        return super.hitTest(point)
    }

    private var matchingSnapshot: SpacePagerPresentation.Snapshot? {
        guard let value = presentation?.snapshot, value.order(of: allSpaces) != nil else { return nil }
        return value
    }

    private func restingSnapshot(_ id: UUID) -> SpacePagerPresentation.Snapshot {
        .init(
            generation: 0, spaceIDs: allSpaces.map(\.id),
            position: CGFloat(allSpaces.firstIndex { $0.id == id } ?? 0), phase: .idle, destinationID: id)
    }

    /// Lays the strip out in `order`.
    private func arrange(_ order: [SpaceModel]) {
        spaces = order
        strip = SpacePageStrip(order, shownPins: shownPins)
    }

    private func receive(_ value: SpacePagerPresentation.Snapshot) {
        guard let order = value.order(of: allSpaces) else { return }
        arrange(order)
        // A selection that arrives mid-slide leaves the roots built for the
        // Space selected before it, so the page it lands on would never take
        // input. A settled slide supplies the latest roots, as the sidebar's
        // pager does.
        let settles = value.phase == .idle && snapshot?.phase != .idle
        let jumps = jumps(from: snapshot, to: value)
        snapshot = value
        if value.phase == .idle { restingSpaceID = value.destinationID }
        if let release = value.transition, value.phase == .settling, bounds.width > 0 {
            if transition == release {
                // Admit the next neighbor once the common native animation has
                // started. Existing visible roots are never refreshed here.
                if preparedDestination != value.destinationID {
                    preparedDestination = value.destinationID
                    prepareHosts(at: value.position, destination: value.destinationID, refresh: false)
                    updateAccessibility()
                }
                return
            }
            prepareHosts(
                at: release.startPosition, destination: value.destinationID, refresh: false,
                preparesNeighbors: false)
            stopAnimations()
            positionHosts(at: release.startPosition)
            transition = release
            if slides {
                let moving = hosts.filter { key, host in
                    needsMotion(
                        host, to: origin(for: key, at: release.endPosition, placedNear: release.startPosition))
                }
                slide(Array(moving.keys), along: release)
            } else {
                fade(along: release)
            }
        } else {
            if jumps { dissolve() }
            stopAnimations()
            prepareHosts(
                at: value.position, destination: value.destinationID, refresh: settles,
                preparesNeighbors: value.phase == .idle)
            positionHosts(at: value.position)
        }
        updateAccessibility()
    }

    /// Moves the pages `keys` name along `release`, with the pager's native
    /// curve.
    private func slide(_ keys: [BrowserSpaceRuntimeAssignment], along release: SpacePagerSettlement) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = release.duration
            context.timingFunction = release.timingFunction
            for key in keys {
                guard let host = hosts[key] else { continue }
                let animation = CABasicAnimation()
                release.configure(animation)
                animation.fromValue = NSValue(point: origin(for: key, at: release.startPosition))
                host.animations = ["frameOrigin": animation]
                host.animator().setFrameOrigin(
                    origin(for: key, at: release.endPosition, placedNear: release.startPosition))
            }
        }
    }

    /// Continues the slide along `release` for the pages `keys` name after a
    /// resize, from the moment it began, so it goes on from where it is
    /// instead of starting over. AppKit installs no animator animation while
    /// it lays a view out, so the pages' layers take the slide directly.
    private func resumeSlide(
        _ keys: [BrowserSpaceRuntimeAssignment], along release: SpacePagerSettlement, beganAt beginTime: CFTimeInterval?
    ) {
        for key in keys {
            guard let host = hosts[key] else { continue }
            let animation = CABasicAnimation(keyPath: "position")
            release.configure(animation)
            // Zero, for a slide Core Animation has not committed yet, starts now.
            animation.beginTime = beginTime ?? 0
            let end = origin(for: key, at: release.endPosition, placedNear: release.startPosition)
            animation.fromValue = NSValue(point: origin(for: key, at: release.startPosition))
            animation.toValue = NSValue(point: end)
            host.setFrameOrigin(end)
            host.layer?.add(animation, forKey: "position")
        }
    }

    /// The pages the running slide moves.
    private var slidingHosts: [BrowserSpaceRuntimeAssignment] {
        hosts.filter { $0.value.layer?.animationKeys()?.isEmpty == false }.map(\.key)
    }

    /// When Core Animation began the running slide, once it has committed it.
    private var slideBeginTime: CFTimeInterval? {
        hosts.values.lazy.compactMap { host -> CFTimeInterval? in
            guard let layer = host.layer, let key = layer.animationKeys()?.first else { return nil }
            return layer.animation(forKey: key)?.beginTime
        }.first { $0 > 0 }
    }

    private func stopAnimations() {
        if transition != nil {
            for host in hosts.values { host.layer?.removeAllAnimations() }
        }
        transition = nil
        preparedDestination = nil
    }

    private func prepareHosts(
        at position: CGFloat, destination: UUID?, refresh: Bool, preparesNeighbors: Bool = true
    ) {
        guard !spaces.isEmpty, let makeRoot else { return }
        let indices = strip.keptIndices(
            at: position, destinationID: destination, selectedSpaceID: selectedSpaceID,
            isMoving: snapshot?.phase != .idle, keepsNeighbors: preparesNeighbors,
            keeps: spaces.indices.filter { hosts[BrowserSpaceRuntimeAssignment(space: spaces[$0])] != nil })
        let required = Set(indices.map { BrowserSpaceRuntimeAssignment(space: spaces[$0]) })
        for key in hosts.keys where !required.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for index in indices.sorted() {
            let space = spaces[index]
            let key = BrowserSpaceRuntimeAssignment(space: space)
            let contentPresentation = contentPresentation(at: index)
            if let host = hosts[key] {
                let previous = host.hostingView.rootView.contentPresentation
                if contentPresentation != .inactive, host.frame.size != bounds.size {
                    host.setFrameSize(bounds.size)
                }
                if previous == .inactive, contentPresentation != .inactive {
                    // Cached geometry may predate a sidebar resize. Restore
                    // the release origin before its native animation starts.
                    host.setFrameOrigin(origin(for: key, at: position))
                    host.alphaValue = opacity(ofPageAt: index, at: position)
                }
                var root =
                    refresh || host.hostingView.rootView.assignment != key
                    ? makeRoot(space, space.id == selectedSpaceID) : host.hostingView.rootView
                root.contentPresentation = contentPresentation
                // A page off screen is hidden as well: on macOS 26, another
                // hosting view beside the selected page can take its clicks.
                host.isHidden = contentPresentation == .inactive || yieldsPlace(at: index)
                if host.hostingView.rootView.content != root.content || previous != contentPresentation {
                    if contentPresentation != .interactive,
                        let responder = window?.firstResponder as? NSView, responder.isDescendant(of: host)
                    {
                        window?.makeFirstResponder(nil)
                    }
                    host.hostingView.rootView = root
                    if previous == .inactive, contentPresentation != .inactive {
                        // Admit the destination before moving its first frame
                        // into view, without refreshing roots on progress ticks.
                        host.hostingView.layoutSubtreeIfNeeded()
                    }
                }
            } else {
                var root = makeRoot(space, space.id == selectedSpaceID)
                root.contentPresentation = contentPresentation
                let host = SpacePageHost(root: root)
                host.frame = CGRect(origin: origin(for: key, at: position), size: bounds.size)
                host.alphaValue = opacity(ofPageAt: index, at: position)
                host.hostingView.frame = host.bounds
                host.isHidden = contentPresentation == .inactive || yieldsPlace(at: index)
                hosts[key] = host
                addSubview(host)
            }
        }
    }

    private func contentPresentation(at index: Int) -> SpaceContentPresentation {
        strip.presentation(at: index, in: snapshot, selectedSpaceID: selectedSpaceID)
    }

    /// Where `key`'s page sits while the strip shows `position`, placed
    /// around the ends as near `reference`: a slide keeps each page where it
    /// began, so none switches ends partway.
    private func origin(
        for key: BrowserSpaceRuntimeAssignment, at position: CGFloat, placedNear reference: CGFloat? = nil
    ) -> CGPoint {
        // Pages that fade all stand in the one place.
        guard slides else { return .zero }
        let index = spaces.firstIndex { $0.id == key.spaceID } ?? 0
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return CGPoint(
            x: strip.offset(ofPageAt: index, at: position, placedNear: reference) * bounds.width * direction, y: 0)
    }

    /// Whether the page at `index` shares its place with the selected
    /// Space's, both showing one page, while the strip moves.
    private func yieldsPlace(at index: Int) -> Bool {
        strip.yieldsPlace(at: index, selectedSpaceID: selectedSpaceID, in: snapshot)
    }

    private func needsMotion(_ host: NSView, to origin: CGPoint) -> Bool {
        host.frame.intersects(bounds) || CGRect(origin: origin, size: bounds.size).intersects(bounds)
    }

    private func positionHosts(at position: CGFloat) {
        for (key, host) in hosts {
            // A release's fade runs on its own; a finger's follows each sample.
            if transition == nil, let index = spaces.firstIndex(where: { $0.id == key.spaceID }) {
                let opacity = opacity(ofPageAt: index, at: position)
                if host.alphaValue != opacity { host.alphaValue = opacity }
                host.layer?.zPosition =
                    slides ? 0 : strip.stacking(ofPageAt: index, at: position, leaving: restingIndex)
            }
            var origin = origin(for: key, at: position)
            if host.hostingView.rootView.contentPresentation == .inactive {
                guard host.frame.intersects(bounds) else { continue }
                // A wider viewport can expose a cached frame. Park it beyond
                // the clip until prepareHosts admits it to a visible slide.
                origin.x =
                    origin.x < 0 ? min(origin.x, -host.frame.width) : max(origin.x, bounds.maxX + host.frame.width)
            }
            if snapshot?.phase == .idle || needsMotion(host, to: origin) {
                if host.frame.origin != origin { host.setFrameOrigin(origin) }
            }
        }
    }

    // MARK: - Actions - Fading

    /// How opaque the page at `index` is while the strip shows `position`:
    /// whole where pages slide, and where they fade, as the strip says.
    private func opacity(ofPageAt index: Int, at position: CGFloat) -> CGFloat {
        slides ? 1 : strip.opacity(ofPageAt: index, at: position, leaving: restingIndex)
    }

    /// Where in the strip the Space it last rested on stands.
    private var restingIndex: Int? {
        restingSpaceID.flatMap { id in spaces.firstIndex { $0.id == id } }
    }

    /// Fades the pages along `release`, on the pager's native curve and clock:
    /// each page's opacity follows the positions the release passes through,
    /// halfway points and crossed Spaces included, as the slide's frames do.
    private func fade(along release: SpacePagerSettlement) {
        let start = release.startPosition
        let end = release.endPosition
        guard end != start else { return }
        let stops = fadeStops(from: start, to: end)
        for (key, host) in hosts where !host.isHidden {
            guard let layer = host.layer, let index = spaces.firstIndex(where: { $0.id == key.spaceID }) else {
                continue
            }
            let values = stops.map {
                strip.opacity(ofPageAt: index, at: $0, leaving: restingIndex, placedNear: start)
            }
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            release.configure(animation)
            animation.values = values.map { NSNumber(value: Double($0)) }
            animation.keyTimes = stops.map { NSNumber(value: Double(($0 - start) / (end - start))) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.zPosition = strip.stacking(
                ofPageAt: index, at: (start + end) / 2, leaving: restingIndex, placedNear: start)
            host.alphaValue = values.last ?? 0
            layer.add(animation, forKey: "spaceTransition.opacity")
            CATransaction.commit()
        }
    }

    /// The positions from `start` to `end` a fade's keyframes stand at: both
    /// ends and every half Space between, where a page's fade bends.
    private func fadeStops(from start: CGFloat, to end: CGFloat) -> [CGFloat] {
        let lower = min(start, end)
        let upper = max(start, end)
        let halves = stride(from: (lower * 2).rounded(.down) / 2, through: upper, by: 0.5).filter {
            $0 > lower && $0 < upper
        }
        return [start] + (end > start ? halves : halves.reversed()) + [end]
    }

    /// Whether, where pages fade, the strip moves from `old` to `new` at once,
    /// with no release to fade along, as a pager that doesn't move under
    /// Reduce Motion does.
    private func jumps(from old: SpacePagerPresentation.Snapshot?, to new: SpacePagerPresentation.Snapshot) -> Bool {
        guard !slides, let old, old.phase == .idle, new.phase == .idle, new.transition == nil,
            old.destinationID != new.destinationID
        else { return false }
        return window != nil && bounds.width > 0
    }

    /// Dissolves what the pages show now into what they show next, on the
    /// pager's standard one-page settle.
    private func dissolve() {
        let transition = CATransition()
        transition.type = .fade
        SpacePagerSettlement.onePage.configure(transition)
        layer?.add(transition, forKey: "spaceDissolve")
    }

    private func updateAccessibility() {
        for (key, host) in hosts {
            host.setAccessibilityHidden(
                snapshot?.phase != .idle || snapshot?.destinationID != selectedSpaceID || key.spaceID != selectedSpaceID
            )
        }
    }
}
