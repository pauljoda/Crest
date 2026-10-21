import AppKit
import Observation

/// Small pictures of one window's recent tabs, kept in memory only and never
/// written anywhere. A tab is pictured as the window leaves it and the panel
/// pictures the tab it opens over; only tabs on the window's recent list keep
/// theirs. Nothing is pictured while the preference is off or the Space is
/// locked.
@MainActor
@Observable
final class BrowserRecentTabSnapshots {
    // MARK: - Static Variables

    /// The width each picture is taken at, in points.
    static let width: CGFloat = 320
    /// Pictures of one tab are never taken closer together than this.
    private static let minimumInterval: TimeInterval = 0.5

    // MARK: - Variables

    private(set) var images: [UUID: NSImage] = [:]
    @ObservationIgnored private let context: BrowserMacWindowContext
    @ObservationIgnored private let isLocked: @MainActor (SpaceModel) -> Bool
    @ObservationIgnored private var lastCaptures: [UUID: Date] = [:]
    @ObservationIgnored private var isFollowing = false

    // MARK: - Initializers

    init(context: BrowserMacWindowContext, isLocked: @escaping @MainActor (SpaceModel) -> Bool) {
        self.context = context
        self.isLocked = isLocked
    }

    // MARK: - Actions - Following

    /// Pictures the tabs the window shows each time it is about to show others.
    /// The change is seen before it lands, while the pages still draw.
    func followShownTabs() {
        guard !isFollowing else { return }
        isFollowing = true
        track()
    }

    private func track() {
        withObservationTracking {
            _ = context.browser.shownCards.map(\.id)
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.capture(self.context.browser.shownCards.map(\.id))
                Task { @MainActor [weak self] in self?.track() }
            }
        }
    }

    // MARK: - Actions - Capturing

    /// Pictures `tabIDs` of the Space the window shows, when they are resident.
    func capture(_ tabIDs: [UUID]) {
        guard RecentTabSwitcherPreference.isOn, let space = context.browser.shownSpace, !isLocked(space) else {
            return
        }
        let now = Date()
        for tabID in tabIDs {
            if let last = lastCaptures[tabID], now.timeIntervalSince(last) < Self.minimumInterval { continue }
            let assignment = BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID)
            guard let page = context.pages.residentPage(matching: assignment) else { continue }
            lastCaptures[tabID] = now
            page.captureViewport(width: Self.width) { [weak self] image in
                guard let self, let image else { return }
                images[tabID] = image
                prune()
            }
        }
    }

    // MARK: - Actions - Keeping

    /// Lets go of the pictures of tabs the window no longer lists.
    func prune() {
        let listed = Set(context.browser.recentTabItems().flatMap(\.tabIDs))
        guard images.keys.contains(where: { !listed.contains($0) }) else { return }
        images = images.filter { listed.contains($0.key) }
        lastCaptures = lastCaptures.filter { listed.contains($0.key) }
    }

    /// Lets go of every picture, as when the preference goes off.
    func removeAll() {
        images = [:]
        lastCaptures = [:]
    }
}
