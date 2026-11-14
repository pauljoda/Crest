import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

// MARK: - Types

/// One tab's picture, compressed, with its proportions.
struct BrowserTabPicture {
    let data: Data
    /// Height over width.
    let aspectRatio: CGFloat
    let takenAt: Date
}

/// Small pictures of the tabs one window's pages showed, which a tab's
/// preview card, a held tab's menu and the recent tabs draw. They are kept in
/// memory only and never written anywhere.
///
/// A tab is pictured once it has shown on screen for a moment, again once it
/// has shown another page or its page has finished loading, and never more
/// often than `minimumGap`, while its page still draws. Its picture keeps the
/// top of the page, as much as a card draws, and stays when the tab goes to
/// sleep, so its card shows how it last looked, until the tab closes or more
/// recently pictured tabs take its place. Nothing is pictured while nothing
/// the window has draws pictures, as `isWanted` tells, or while the Space is
/// locked, and once nothing does, every picture goes.
@MainActor
@Observable
final class BrowserTabPictures {
    // MARK: - Static Variables

    /// The width each picture is taken at, in points.
    static let width: CGFloat = 320
    /// Pictures of one tab are never taken closer together than this, so a
    /// page that rewrites its address as it is used, as a map does, is
    /// pictured at most this often. A change inside it is pictured once it
    /// passes.
    private static let minimumGap: TimeInterval = 10
    /// Pictures of one tab at one address are never taken closer together
    /// than this unless its page finished loading since, so going back and
    /// forth between tabs costs one picture each, not one per switch; the
    /// tab the recent tabs open over is pictured again as they open.
    private static let minimumInterval: TimeInterval = 30
    /// The tallest a picture is kept, as height over width. A taller page
    /// keeps its top, which is as much as a card draws.
    private nonisolated static let tallestAspectRatio: CGFloat = 0.75
    /// How long a tab shows before it is pictured, so a switch never waits on
    /// a picture and a tab passed through on the way to another is skipped.
    private static let settleDelay: Duration = .milliseconds(1500)
    /// How many tabs keep a picture. The least recently pictured go first.
    private static let capacity = 100
    /// How much each picture is compressed, from 0 (most) to 1 (least).
    private nonisolated static let quality = 0.7

    // MARK: - Variables

    private(set) var pictures: [UUID: BrowserTabPicture] = [:]
    @ObservationIgnored private weak var pages: (any BrowserPageOwner)?
    /// Whether something the window has draws pictures.
    @ObservationIgnored private let wanted: @MainActor () -> Bool
    @ObservationIgnored private var isLocked: (@MainActor (SpaceModel) -> Bool)?
    /// When each tab was last pictured, and at which address.
    @ObservationIgnored private var lastCaptures: [UUID: (date: Date, url: String?)] = [:]
    @ObservationIgnored private var settling: Task<Void, Never>?

    /// Whether a feature that draws pictures is on.
    private var isWanted: Bool { wanted() }

    // MARK: - Initializers

    /// Pictures `pages`' tabs while `wanted` says something the window has
    /// draws them, reading what it reads so turning that off lets go of them.
    init(pages: any BrowserPageOwner, wanted: @escaping @MainActor () -> Bool) {
        self.pages = pages
        self.wanted = wanted
    }

    // MARK: - Actions - Following

    /// Pictures the tabs the window shows once they have shown for a moment,
    /// each time it shows others, one of them goes to another page, or one
    /// of their pages comes back, as the shown tab's does after launch, or
    /// comes on screen, as a phone's does when its page comes up, and again
    /// once one of their pages finishes loading. `isLocked` tells a locked
    /// Space, whose tabs are never pictured.
    func follow(isLocked: @escaping @MainActor (SpaceModel) -> Bool) {
        guard self.isLocked == nil else { return }
        self.isLocked = isLocked
        settle()
        trackShownTabs()
        trackLoading()
        trackPreferences()
    }

    private func trackShownTabs() {
        guard let pages else { return }
        withObservationTracking {
            let presented = pages.presentedTabIDsAcrossWindows
            for tab in pages.browser.shownCards {
                _ = (tab.url, pages.host.residentTabIDs.contains(tab.id), presented.contains(tab.id))
            }
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.settle()
                self?.trackShownTabs()
            }
        }
    }

    /// Pictures the shown tabs again once none of their pages is loading
    /// any more, as a page half drawn when first pictured is drawn now.
    private func trackLoading() {
        withObservationTracking {
            _ = shownPagesLoading
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !shownPagesLoading { settle(refreshing: true) }
                trackLoading()
            }
        }
    }

    /// Whether a page of a tab the window shows is loading.
    private var shownPagesLoading: Bool {
        guard let pages, let space = pages.browser.shownSpace else { return false }
        return pages.browser.shownCards.contains { tab in
            let assignment = BrowserTabRuntimeAssignment(tabID: tab.id, spaceID: space.id, profileID: space.profileID)
            return pages.host.page(matching: assignment)?.live.isLoading == true
        }
    }

    /// Lets go of every picture once nothing draws them, and pictures what
    /// the window shows once something does again.
    private func trackPreferences() {
        withObservationTracking {
            _ = isWanted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isWanted { settle() } else { removeAll() }
                trackPreferences()
            }
        }
    }

    /// Pictures what the window shows after `delay`, unless it shows
    /// something else by then, `refreshing` its pictures as `capture` does.
    private func settle(after delay: Duration = BrowserTabPictures.settleDelay, refreshing: Bool = false) {
        settling?.cancel()
        settling = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let pages else { return }
            capture(pages.browser.shownCards.map(\.id), refreshing: refreshing)
        }
    }

    // MARK: - Actions - Capturing

    /// Pictures `tabIDs` of the Space the window shows, when their pages are
    /// resident and on screen, as a web view draws only there. A tab pictured
    /// at the same address moments ago is skipped unless `refreshing`, and a
    /// change within `minimumGap` of its last picture waits until the gap
    /// passes.
    func capture(_ tabIDs: [UUID], refreshing: Bool = false) {
        guard isWanted, let pages, let isLocked, let space = pages.browser.shownSpace, !isLocked(space) else {
            return
        }
        let now = Date()
        let presented = pages.presentedTabIDsAcrossWindows
        var wait: TimeInterval?
        for tabID in tabIDs where presented.contains(tabID) && pages.host.residentTabIDs.contains(tabID) {
            let url = space.tabs.model(tabID)?.url
            if let last = lastCaptures[tabID] {
                let elapsed = now.timeIntervalSince(last.date)
                guard elapsed >= Self.minimumGap else {
                    if refreshing || last.url != url { wait = min(wait ?? .infinity, Self.minimumGap - elapsed) }
                    continue
                }
                if !refreshing, last.url == url, elapsed < Self.minimumInterval { continue }
            }
            let assignment = BrowserTabRuntimeAssignment(tabID: tabID, spaceID: space.id, profileID: space.profileID)
            guard let page = pages.host.page(matching: assignment) else { continue }
            lastCaptures[tabID] = (now, url)
            page.enginePage.capture(width: Self.width) { [weak self] png in
                guard let png else { return }
                Task { @MainActor [weak self] in
                    guard let picture = await Self.compressed(png, takenAt: now), let self, isWanted else { return }
                    pictures[tabID] = picture
                    prune()
                }
            }
        }
        if let wait { settle(after: .seconds(wait), refreshing: refreshing) }
    }

    /// `png` as a compressed picture, made off the main thread.
    private nonisolated static func compressed(_ png: Data, takenAt: Date) async -> BrowserTabPicture? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                let whole = CGImageSourceCreateImageAtIndex(source, 0, nil), whole.width > 0
            else { return nil }
            let tallest = Int((CGFloat(whole.width) * tallestAspectRatio).rounded())
            let image =
                whole.height > tallest
                ? whole.cropping(to: CGRect(x: 0, y: 0, width: whole.width, height: tallest)) ?? whole : whole
            let data = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil)
            else { return nil }
            CGImageDestinationAddImage(
                destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { return nil }
            return BrowserTabPicture(
                data: data as Data, aspectRatio: CGFloat(image.height) / CGFloat(image.width), takenAt: takenAt)
        }.value
    }

    // MARK: - Actions - Keeping

    /// Lets go of the pictures of tabs that closed, and of the least recently
    /// pictured past `capacity`.
    private func prune() {
        guard let pages else { return }
        let open = Set(pages.browser.workspaceModel?.spaces.models.flatMap { $0.tabs.models.map(\.id) } ?? [])
        var kept = pictures.filter { open.contains($0.key) }
        if kept.count > Self.capacity {
            let newest = kept.sorted { $0.value.takenAt > $1.value.takenAt }.prefix(Self.capacity).map(\.key)
            kept = kept.filter { Set(newest).contains($0.key) }
        }
        guard kept.count != pictures.count else { return }
        pictures = kept
        lastCaptures = lastCaptures.filter { kept.keys.contains($0.key) }
    }

    /// Lets go of every picture, as when nothing draws them or a private
    /// window closes.
    func removeAll() {
        settling?.cancel()
        guard !pictures.isEmpty || !lastCaptures.isEmpty else { return }
        pictures = [:]
        lastCaptures = [:]
    }
}
