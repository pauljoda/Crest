import SwiftUI

/// The touch host's half of the shared Space page strip: where each Space's
/// page card stands while the sidebar's pager moves.
///
/// The pager's native scrolling is the clock. It publishes its position on
/// every scroll frame, tracking a finger and settling alike, and the cards
/// follow it, so the page slides with the sidebar and comes to rest with it.
/// `SpacePageStrip` decides which cards are on show and where they stand, as
/// it does for the Mac's pages. Nothing here selects a Space: the pager
/// commits the one it comes to rest on, and the page area then shows that
/// Space's own page where its card already stands. Under Reduce Motion the
/// page area shows the shown card alone, which changes when the switch lands.
@MainActor @Observable
final class MobileSpacePageMotion {
    // MARK: - Variables

    /// Where the strip stands, in Spaces along its order, as the pager last
    /// published it.
    private(set) var position: CGFloat = 0
    /// The Spaces in the order the pager's position runs along, and where
    /// each card stands along it.
    private(set) var strip = SpacePageStrip([], shownPins: [:])
    /// The Spaces whose cards the page area draws now, the shown one's among
    /// them. It changes only as the strip crosses a Space, never on every
    /// frame.
    private(set) var pageSpaceIDs: [UUID] = []
    /// Whether the cards follow the pager.
    private(set) var slides = true
    /// The page area's width, which turns Spaces into points.
    private(set) var pageWidth: CGFloat = 0
    /// The Space a slide last came to rest on, until another movement
    /// begins. Its card stays under the shown one's while that one's pages
    /// draw, so what slid in shows until they have.
    private(set) var landedSpaceID: UUID?
    /// The pager publishing the position this window's cards follow.
    @ObservationIgnored private weak var presentation: SpacePagerPresentation?
    /// The pager's latest position for these Spaces.
    @ObservationIgnored private var snapshot: SpacePagerPresentation.Snapshot?
    /// Every Space in its order.
    @ObservationIgnored private var spaces: [SpaceModel] = []
    /// The pinned tab each Space shows, for the Spaces that show one.
    @ObservationIgnored private var shownPins: [UUID: UUID] = [:]
    /// The Space the page area shows.
    @ObservationIgnored private var shownSpaceID: UUID?
    /// Whether the strip stands where `rest(on:)` put it, as no pager has
    /// published a position for these Spaces yet.
    @ObservationIgnored private var restsWithoutPager = false

    // MARK: - Actions - Presentation

    /// Follows `presentation`, the pager of a window whose Spaces are
    /// `spaces` and which shows `shownSpaceID`, where `shownPins` is the
    /// pinned tab each Space shows, for those that show one. Cards slide when
    /// `slides`.
    func follow(
        _ presentation: SpacePagerPresentation?, spaces: [SpaceModel], shownSpaceID: UUID?,
        shownPins: [UUID: UUID], slides: Bool
    ) {
        let showsAnother = self.shownSpaceID != nil && self.shownSpaceID != shownSpaceID
        if showsAnother { landedSpaceID = slides ? shownSpaceID : nil }
        self.spaces = spaces
        self.shownPins = shownPins
        self.shownSpaceID = shownSpaceID
        if self.slides != slides { self.slides = slides }
        if self.presentation !== presentation {
            self.presentation?.removeObserver(owner: self)
            self.presentation = presentation
            snapshot = nil
            presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        }
        // A strip no pager has moved yet stands on the Space shown now.
        if snapshot?.order(of: spaces) == nil || (restsWithoutPager && showsAnother) {
            rest(on: shownSpaceID)
        } else {
            arrange()
        }
    }

    func stopFollowing() {
        presentation?.removeObserver(owner: self)
        presentation = nil
    }

    /// Measures the page area, `width` points across.
    func measure(_ width: CGFloat) {
        if pageWidth != width { pageWidth = width }
    }

    /// How far toward the trailing edge the card of the Space `spaceID`
    /// stands, in points, as SwiftUI offsets a view in either writing
    /// direction.
    func offset(of spaceID: UUID) -> CGFloat {
        guard slides, let index = strip.spaceIDs.firstIndex(of: spaceID) else { return 0 }
        return strip.offset(ofPageAt: index, at: position) * pageWidth
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot) {
        guard snapshot.order(of: spaces) != nil, snapshot.position.isFinite else { return }
        if snapshot.phase != .idle, landedSpaceID != nil { landedSpaceID = nil }
        // A strip at rest stands exactly on a Space.
        let rounded = snapshot.position.rounded()
        let position =
            snapshot.phase == .idle && abs(snapshot.position - rounded) < 0.001 ? rounded : snapshot.position
        self.snapshot = snapshot
        restsWithoutPager = false
        if self.position != position { self.position = position }
        arrange()
    }

    /// Stands the strip on `spaceID`, for a pager that has published nothing
    /// for these Spaces yet.
    private func rest(on spaceID: UUID?) {
        let index = spaceID.flatMap { id in spaces.firstIndex { $0.id == id } } ?? 0
        snapshot = SpacePagerPresentation.Snapshot(
            generation: 0, spaceIDs: spaces.map(\.id), position: CGFloat(index), phase: .idle,
            destinationID: spaceID)
        restsWithoutPager = true
        if position != CGFloat(index) { position = CGFloat(index) }
        arrange()
    }

    /// Lays the strip out in the order the snapshot runs along, and finds the
    /// cards on show where cards slide. One that shares its place with the
    /// shown Space's, showing the same page, leaves the page to it.
    private func arrange() {
        guard let snapshot else { return }
        let next = SpacePageStrip(snapshot.order(of: spaces) ?? spaces, shownPins: shownPins)
        if strip != next { strip = next }
        let pages = strip.spaceIDs.indices.filter { index in
            slides && strip.presentation(at: index, in: snapshot, selectedSpaceID: shownSpaceID) != .inactive
                && !strip.yieldsPlace(at: index, selectedSpaceID: shownSpaceID, in: snapshot)
        }.map { strip.spaceIDs[$0] }
        if pageSpaceIDs != pages { pageSpaceIDs = pages }
    }
}
