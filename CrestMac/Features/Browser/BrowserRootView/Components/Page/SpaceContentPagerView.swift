import AppKit
import QuartzCore
import SwiftUI

/// A passive strip of real content surfaces. Only the sidebar owns gestures;
/// web history gestures continue to belong to WebKit.
@MainActor
final class SpaceContentPagerView<Content: View>: NSView {
    private var spaces: [BrowserSpace] = []
    private var selectedSpaceID: SpaceID?
    private var lockedSpaceIDs: Set<SpaceID> = []
    private var layoutDirection = LayoutDirection.leftToRight
    private var presentation: SpacePagerPresentation?
    private var snapshot: SpacePagerPresentation.Snapshot?
    private var transition: SpacePagerSettlement?
    private var hosts: [BrowserSpaceRuntimeAssignment: SpacePageHost<Content>] = [:]
    private var makeRoot: ((BrowserSpace, Bool) -> SpacePageRoot<Content>)?
    private var lastSize = CGSize.zero
    private var preparedDestination: SpaceID?

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

    func update(
        spaces: [BrowserSpace], selectedSpaceID: SpaceID, lockedSpaceIDs: Set<SpaceID>,
        layoutDirection: LayoutDirection, presentation: SpacePagerPresentation?,
        makeRoot: @escaping (BrowserSpace, Bool) -> SpacePageRoot<Content>
    ) {
        let changedLocks = self.lockedSpaceIDs.symmetricDifference(lockedSpaceIDs)
        let assignments = Set(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        // Withdraw old clear surfaces before admitting roots for a new lock or
        // profile assignment. In-flight reversal cannot resurrect those hosts.
        for key in hosts.keys where changedLocks.contains(key.spaceID) || !assignments.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.lockedSpaceIDs = lockedSpaceIDs
        self.layoutDirection = layoutDirection
        self.makeRoot = makeRoot
        if self.presentation !== presentation {
            disconnect()
            self.presentation = presentation
            presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        }
        let current = matchingSnapshot ?? restingSnapshot(selectedSpaceID)
        snapshot = current
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
        transition = nil
        for host in hosts.values {
            host.layer?.removeAllAnimations()
            host.setFrameSize(bounds.size)
        }
        if let snapshot {
            prepareHosts(
                at: snapshot.position, destination: snapshot.destinationID, refresh: false,
                preparesNeighbors: snapshot.phase == .idle)
            positionHosts(at: snapshot.position)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(convert(point, from: superview)),
            snapshot?.phase == .idle, snapshot?.destinationID == selectedSpaceID
        else { return nil }
        return super.hitTest(point)
    }

    private var matchingSnapshot: SpacePagerPresentation.Snapshot? {
        guard let value = presentation?.snapshot, value.spaceIDs == spaces.map(\.id) else { return nil }
        return value
    }

    private func restingSnapshot(_ id: SpaceID) -> SpacePagerPresentation.Snapshot {
        .init(
            generation: 0, spaceIDs: spaces.map(\.id),
            position: CGFloat(spaces.firstIndex { $0.id == id } ?? 0), phase: .idle, destinationID: id)
    }

    private func receive(_ value: SpacePagerPresentation.Snapshot) {
        guard value.spaceIDs == spaces.map(\.id) else { return }
        snapshot = value
        if let release = value.transition, value.phase == .settling, bounds.width > 0 {
            if transition == release {
                // Admit the next neighbor once the common native animation has
                // started. Existing visible roots are never refreshed here.
                if preparedDestination != value.destinationID {
                    preparedDestination = value.destinationID
                    prepareHosts(at: value.position, destination: value.destinationID, refresh: false)
                }
                return
            }
            prepareHosts(
                at: release.startPosition, destination: value.destinationID, refresh: false,
                preparesNeighbors: false)
            stopAnimations()
            positionHosts(at: release.startPosition)
            transition = release
            NSAnimationContext.runAnimationGroup { context in
                context.duration = release.duration
                context.timingFunction = release.timingFunction
                for (key, host) in hosts {
                    let end = origin(for: key, at: release.endPosition)
                    guard needsMotion(host, to: end) else { continue }
                    let animation = CABasicAnimation()
                    release.configure(animation)
                    animation.fromValue = NSValue(point: host.frame.origin)
                    host.animations = ["frameOrigin": animation]
                    host.animator().setFrameOrigin(end)
                }
            }
        } else {
            stopAnimations()
            prepareHosts(
                at: value.position, destination: value.destinationID, refresh: false,
                preparesNeighbors: value.phase == .idle)
            positionHosts(at: value.position)
        }
        updateAccessibility()
    }

    private func stopAnimations() {
        if transition != nil {
            for host in hosts.values { host.layer?.removeAllAnimations() }
        }
        transition = nil
        preparedDestination = nil
    }

    private func prepareHosts(
        at position: CGFloat, destination: SpaceID?, refresh: Bool, preparesNeighbors: Bool = true
    ) {
        guard !spaces.isEmpty, let makeRoot else { return }
        let center = min(spaces.count - 1, max(0, Int(position.rounded())))
        let target = destination.flatMap { id in spaces.firstIndex { $0.id == id } } ?? center
        let visible = Set([Int(position.rounded(.down)), Int(position.rounded(.up)), target])
        let neighbors = preparesNeighbors ? [target - 1, target + 1, center - 1, center + 1] : []
        var indices = visible.filter { spaces.indices.contains($0) }
        for index in neighbors where indices.count < 4 && spaces.indices.contains(index) { indices.insert(index) }
        let cached = spaces.indices.filter { hosts[BrowserSpaceRuntimeAssignment(space: spaces[$0])] != nil }
            .sorted { abs($0 - target) < abs($1 - target) }
        for index in cached where indices.count < 4 { indices.insert(index) }
        let required = Set(indices.map { BrowserSpaceRuntimeAssignment(space: spaces[$0]) })
        for key in hosts.keys where !required.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for index in indices.sorted() {
            let space = spaces[index]
            let key = BrowserSpaceRuntimeAssignment(space: space)
            if let host = hosts[key] {
                if refresh { host.hostingView.rootView = makeRoot(space, space.id == selectedSpaceID) }
            } else {
                let host = SpacePageHost(root: makeRoot(space, space.id == selectedSpaceID))
                host.frame = CGRect(origin: origin(for: key, at: position), size: bounds.size)
                host.hostingView.frame = host.bounds
                hosts[key] = host
                addSubview(host)
            }
        }
    }

    private func origin(for key: BrowserSpaceRuntimeAssignment, at position: CGFloat) -> CGPoint {
        let index = spaces.firstIndex { $0.id == key.spaceID } ?? 0
        let direction: CGFloat = layoutDirection == .leftToRight ? 1 : -1
        return CGPoint(x: (CGFloat(index) - position) * bounds.width * direction, y: 0)
    }

    private func needsMotion(_ host: NSView, to origin: CGPoint) -> Bool {
        host.frame.intersects(bounds) || CGRect(origin: origin, size: bounds.size).intersects(bounds)
    }

    private func positionHosts(at position: CGFloat) {
        for (key, host) in hosts {
            let origin = origin(for: key, at: position)
            if snapshot?.phase == .idle || needsMotion(host, to: origin) {
                if host.frame.origin != origin { host.setFrameOrigin(origin) }
            }
        }
    }

    private func updateAccessibility() {
        for (key, host) in hosts {
            host.setAccessibilityHidden(
                snapshot?.phase != .idle || snapshot?.destinationID != selectedSpaceID || key.spaceID != selectedSpaceID
            )
        }
    }
}
