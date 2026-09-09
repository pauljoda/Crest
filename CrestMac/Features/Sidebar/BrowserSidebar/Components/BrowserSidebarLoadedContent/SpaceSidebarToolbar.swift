import AppKit
import SwiftUI

/// Extension controls stay under the fixed address field. Only their native
/// position and opacity follow paging; their actions and artwork are prepared in retained roots.
struct SpaceSidebarToolbar: NSViewRepresentable {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let toolbarSpaces: Set<SpaceID>
    let contentTopInsets: [SpaceID: CGFloat]
    let extensionControllerPool: BrowserExtensionControllerPool
    let spaceAccess: BrowserSpaceAccessController

    func makeNSView(context: Context) -> SpaceSidebarToolbarView {
        SpaceSidebarToolbarView(frame: .zero)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: SpaceSidebarToolbarView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: SpaceSidebarToolbarView, context: Context) {
        view.update(
            spaces: spaces, selectedSpaceID: selectedSpaceID, toolbarSpaces: toolbarSpaces,
            contentTopInsets: contentTopInsets, reduceMotion: context.environment.accessibilityReduceMotion,
            presentation: context.environment.spacePagerPresentation
        ) { space in
            SpaceSidebarToolbarRoot(
                space: space, pool: extensionControllerPool, isLocked: spaceAccess.isLocked(space),
                actions: toolbarSpaces.contains(space.id)
                    ? extensionControllerPool.pinnedActionPresentations(in: space.id, tabID: space.selectedTabID) : [])
        }
    }

    static func dismantleNSView(_ view: SpaceSidebarToolbarView, coordinator: ()) {
        view.disconnect()
    }
}

struct SpaceSidebarToolbarRoot: View {
    let space: BrowserSpace
    let pool: BrowserExtensionControllerPool
    let isLocked: Bool
    let actions: [BrowserExtensionActionPresentation]

    var body: some View {
        BrowserPinnedExtensionStrip(
            spaceID: space.id, selectedTabID: space.selectedTabID, extensionControllerPool: pool,
            actionPresentationOverride: actions
        )
        .padding(.top, BrowserPinnedExtensionStripLayoutPolicy.adjacentSpacing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, BrowserSpaceForegroundPolicy.colorScheme(for: space.branding))
        .blur(radius: isLocked ? BrowserSidebarMetrics.lockedSpaceBlurRadius : 0)
        .redacted(reason: isLocked ? .placeholder : [])
        .allowsHitTesting(!isLocked)
        .accessibilityHidden(isLocked)
    }
}

@MainActor
final class SpaceSidebarToolbarView: NSView {
    private var spaces: [BrowserSpace] = []
    private var selectedSpaceID: SpaceID?
    private var toolbarSpaces: Set<SpaceID> = []
    private var presentation: SpacePagerPresentation?
    private var makeRoot: ((BrowserSpace) -> SpaceSidebarToolbarRoot)?
    private var hosts: [BrowserSpaceRuntimeAssignment: SpacePageHost<SpaceSidebarToolbarRoot>] = [:]
    private var pendingRoots: [BrowserSpaceRuntimeAssignment: SpaceSidebarToolbarRoot] = [:]
    private var contentTopInsets: [SpaceID: CGFloat] = [:]
    private var pendingContentTopInsets: [SpaceID: CGFloat] = [:]
    private var reduceMotion = false
    private var activeTransition: SpacePagerSettlement?

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

    override func layout() {
        super.layout()
        for host in hosts.values where host.frame.size != bounds.size { host.setFrameSize(bounds.size) }
        receive(presentation?.snapshot)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local), !isHiddenOrHasHiddenAncestor,
            presentation?.snapshot?.phase != .tracking, presentation?.snapshot?.phase != .settling,
            let selectedSpaceID, toolbarSpaces.contains(selectedSpaceID),
            let space = spaces.first(where: { $0.id == selectedSpaceID })
        else { return nil }
        return hosts[BrowserSpaceRuntimeAssignment(space: space)]?.hitTest(local)
    }

    func update(
        spaces: [BrowserSpace], selectedSpaceID: SpaceID, toolbarSpaces: Set<SpaceID>,
        contentTopInsets: [SpaceID: CGFloat], reduceMotion: Bool = false,
        presentation: SpacePagerPresentation?, makeRoot: @escaping (BrowserSpace) -> SpaceSidebarToolbarRoot
    ) {
        let reconnects = self.presentation !== presentation
        if reconnects { disconnect() }
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.toolbarSpaces = toolbarSpaces
        pendingContentTopInsets = contentTopInsets
        self.reduceMotion = reduceMotion
        self.presentation = presentation
        self.makeRoot = makeRoot
        let valid = Set(spaces.map(BrowserSpaceRuntimeAssignment.init(space:)))
        for key in hosts.keys where !valid.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        pendingRoots.removeAll(keepingCapacity: true)
        for space in spaces {
            let key = BrowserSpaceRuntimeAssignment(space: space)
            guard let host = hosts[key] else { continue }
            let root = makeRoot(space)
            pendingRoots[key] = root
            // Access changes must redact retained controls immediately, even
            // if ordinary action updates are waiting for the swipe to finish.
            if root.isLocked != host.hostingView.rootView.content.isLocked {
                host.hostingView.rootView = SpacePageRoot(content: root, assignment: key)
            }
        }
        if reconnects {
            presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        }
        receive(presentation?.snapshot)
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        activeTransition = nil
        pendingRoots.removeAll()
        for host in hosts.values { host.layer?.removeAllAnimations() }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot?) {
        guard !spaces.isEmpty, bounds.width > 0, bounds.height > 0, let makeRoot else { return }
        let matches = snapshot?.spaceIDs == spaces.map(\.id)
        let position = matches ? snapshot?.position ?? 0 : CGFloat(spaces.firstIndex { $0.id == selectedSpaceID } ?? 0)
        guard let blend = SpacePagerInterpolation(position: position, count: spaces.count) else { return }
        let isIdle = !matches || snapshot?.phase == .idle || snapshot == nil
        if isIdle, !pendingRoots.isEmpty {
            for (key, root) in pendingRoots {
                hosts[key]?.hostingView.rootView = SpacePageRoot(content: root, assignment: key)
            }
            pendingRoots.removeAll(keepingCapacity: true)
        }
        let insetChanged = isIdle && contentTopInsets != pendingContentTopInsets
        if isIdle { contentTopInsets = pendingContentTopInsets }
        let transition = matches ? snapshot?.transition : nil
        if transition != nil, activeTransition == transition { return }
        let destination = min(spaces.count - 1, max(0, Int((transition?.endPosition ?? position).rounded())))
        let range = Set(
            [blend.lower, blend.upper] + Array(max(0, destination - 1)...min(spaces.count - 1, destination + 1))
        ).sorted()
        let required = Set(range.map { BrowserSpaceRuntimeAssignment(space: spaces[$0]) })
        for key in hosts.keys where !required.contains(key) {
            hosts.removeValue(forKey: key)?.removeFromSuperview()
        }
        for index in range {
            let space = spaces[index]
            let key = BrowserSpaceRuntimeAssignment(space: space)
            if hosts[key] == nil {
                let host = SpacePageHost(root: SpacePageRoot(content: makeRoot(space), assignment: key))
                host.frame = CGRect(x: 0, y: verticalOffset(at: position), width: bounds.width, height: bounds.height)
                host.hostingView.frame = host.bounds
                hosts[key] = host
                addSubview(host)
            }
            guard let host = hosts[key], let layer = host.layer else { continue }
            host.setAccessibilityHidden(space.id != selectedSpaceID || !isIdle)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let previousY = layer.presentation()?.frame.minY ?? host.frame.minY
            if let transition {
                host.setFrameOrigin(NSPoint(x: 0, y: verticalOffset(at: transition.endPosition)))
                transition.animate(
                    layer, keyPath: "position.y",
                    values: transition.positions.map {
                        verticalOffset(at: $0) + host.bounds.height * layer.anchorPoint.y
                    })
                transition.animate(
                    layer, keyPath: "opacity",
                    values: transition.positions.map {
                        Float(max(0, 1 - abs($0 - CGFloat(index))))
                    })
            } else {
                layer.removeAnimation(forKey: "spaceTransition.position.y")
                host.setFrameOrigin(NSPoint(x: 0, y: verticalOffset(at: position)))
                if insetChanged, !reduceMotion, abs(previousY - host.frame.minY) > 0.01 {
                    let animation = CABasicAnimation(keyPath: "position.y")
                    SpacePagerSettlement(startPosition: 0, endPosition: 1, generation: 0).configure(animation)
                    animation.isAdditive = true
                    animation.fromValue = previousY - host.frame.minY
                    animation.toValue = 0
                    layer.add(animation, forKey: "sidebarInsetChange")
                }
                layer.removeAnimation(forKey: "spaceTransition.opacity")
                layer.opacity = Float(max(0, 1 - abs(position - CGFloat(index))))
            }
            CATransaction.commit()
        }
        activeTransition = transition
    }
    /// The strip's bottom edge meets the tab list's top edge. Sliding out from
    /// behind the address field prevents translucent controls overlapping pins.
    private func verticalOffset(at position: CGFloat) -> CGFloat {
        guard let blend = SpacePagerInterpolation(position: position, count: spaces.count) else { return 0 }
        let lower = contentTopInsets[spaces[blend.lower].id] ?? bounds.height
        let upper = contentTopInsets[spaces[blend.upper].id] ?? bounds.height
        return lower + (upper - lower) * blend.fraction - bounds.height
    }

}
