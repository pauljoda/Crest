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
/// A tab is pictured once it has shown on screen for a moment, and again once
/// it has shown another page for a moment, while its page still draws. Its
/// picture stays when the tab goes to sleep, so its card shows how it last
/// looked, until the tab closes or more recently pictured tabs take its
/// place. Nothing is pictured while nothing the window has draws pictures,
/// as `isWanted` tells, or while the Space is locked, and once nothing does,
/// every picture goes.
@MainActor
@Observable
final class BrowserTabPictures {
    // MARK: - Static Variables

    /// The width each picture is taken at, in points.
    static let width: CGFloat = 320
    /// Pictures of one tab at one address are never taken closer together
    /// than this, so going back and forth between tabs costs one picture
    /// each, not one per switch; the tab the recent tabs open over is
    /// pictured again as they open.
    private static let minimumInterval: TimeInterval = 30
    /// How long a tab shows before it is pictured, so a switch never waits on
    /// a picture and a tab passed through on the way to another is skipped.
    private static let settleDelay: Duration = .milliseconds(1500)
    /// How many tabs keep a picture. The least recently pictured go first.
    private static let capacity = 100
    /// How much each picture is compressed, from 0 (most) to 1 (least).
    private nonisolated static let quality = 0.7

    // MARK: - Variables

    private(set) var pictures: [UUID: BrowserTabPicture] = [:]
    @ObservationIgnored private unowned let pages: any BrowserPageOwner
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
    /// comes on screen, as a phone's does when its page comes up.
    /// `isLocked` tells a locked Space, whose tabs are never pictured.
    func follow(isLocked: @escaping @MainActor (SpaceModel) -> Bool) {
        guard self.isLocked == nil else { return }
        self.isLocked = isLocked
        settle()
        trackShownTabs()
        trackPreferences()
    }

    private func trackShownTabs() {
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

    /// Lets go of every picture once nothing draws them.
    private func trackPreferences() {
        withObservationTracking {
            _ = isWanted
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !isWanted { removeAll() }
                trackPreferences()
            }
        }
    }

    /// Pictures what the window shows after `settleDelay`, unless it shows
    /// something else by then.
    private func settle() {
        settling?.cancel()
        settling = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            capture(pages.browser.shownCards.map(\.id))
        }
    }

    // MARK: - Actions - Capturing

    /// Pictures `tabIDs` of the Space the window shows, when their pages are
    /// resident and on screen, as a web view draws only there, skipping a tab
    /// pictured at the same address moments ago unless `refreshing`.
    func capture(_ tabIDs: [UUID], refreshing: Bool = false) {
        guard isWanted, let isLocked, let space = pages.browser.shownSpace, !isLocked(space) else { return }
        let now = Date()
        let presented = pages.presentedTabIDsAcrossWindows
        for tabID in tabIDs where presented.contains(tabID) && pages.host.residentTabIDs.contains(tabID) {
            let url = space.tabs.model(tabID)?.url
            if !refreshing, let last = lastCaptures[tabID], last.url == url,
                now.timeIntervalSince(last.date) < Self.minimumInterval
            {
                continue
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
    }

    /// `png` as a compressed picture, made off the main thread.
    private nonisolated static func compressed(_ png: Data, takenAt: Date) async -> BrowserTabPicture? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width > 0
            else { return nil }
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
