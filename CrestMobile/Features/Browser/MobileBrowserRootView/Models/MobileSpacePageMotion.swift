import SwiftUI

/// The touch host's half of the shared Space page strip: where each Space's
/// page card stands while the sidebar's pager moves, or how opaque it is
/// where pages fade rather than slide.
///
/// The pager's native scrolling is the clock. It publishes its position on
/// every scroll frame, tracking a finger and settling alike, and the cards
/// follow it, so the page slides or fades with the sidebar and comes to rest
/// with it. `SpacePageStrip` decides which cards are on show, where they stand
/// and how opaque they are, as it does for the Mac's pages. Nothing here
/// selects a Space: the pager commits the one it comes to rest on, and the
/// page area then shows that Space's own page where its card already stands.
@MainActor @Observable
final class MobileSpacePageMotion {
    // MARK: - Types

    /// A fade the cards make where the pager jumped instead of moving.
    private struct Jump: Equatable {
        let settlement: SpacePagerSettlement
        /// The Space the jump reaches.
        let destinationID: UUID?
    }

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
    /// Whether the cards slide with the pager, or keep their place and fade.
    private(set) var slides = true
    /// The Space the strip last came to rest on, which a fade leaves.
    private(set) var restingSpaceID: UUID?
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
    /// The move the cards fade along where the pager jumped instead of
    /// moving, as it does under Reduce Motion, until it ends.
    @ObservationIgnored private var jump: Jump?
    /// Whether the strip stands where `rest(on:)` put it, as no pager has
    /// published a position for these Spaces yet.
    @ObservationIgnored private var restsWithoutPager = false
    /// Counts the jumps faded, so a fade's completion can tell itself from a
    /// later one between the same positions.
    @ObservationIgnored private var jumpCount: UInt = 0

    // MARK: - Actions - Presentation

    /// Follows `presentation`, the pager of a window whose Spaces are
    /// `spaces` and which shows `shownSpaceID`, where `shownPins` is the
    /// pinned tab each Space shows, for those that show one. Cards slide when
    /// `slides`, and fade otherwise.
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
    /// stands while the strip shows `position`, in points, as SwiftUI offsets
    /// a view in either writing direction.
    func offset(of spaceID: UUID, at position: CGFloat) -> CGFloat {
        guard slides, let index = strip.spaceIDs.firstIndex(of: spaceID) else { return 0 }
        return strip.offset(ofPageAt: index, at: position) * pageWidth
    }

    /// How opaque the card of the Space `spaceID` is while the strip shows
    /// `position`: whole where cards slide, and where they fade, as the strip
    /// says.
    func opacity(of spaceID: UUID, at position: CGFloat) -> Double {
        guard !slides, let index = strip.spaceIDs.firstIndex(of: spaceID) else { return 1 }
        return Double(strip.opacity(ofPageAt: index, at: position, leaving: restingIndex))
    }

    /// Where the card of the Space `spaceID` stacks while cards fade, the
    /// one fading in above the one it covers.
    func stacking(of spaceID: UUID, at position: CGFloat) -> Double {
        guard let index = strip.spaceIDs.firstIndex(of: spaceID) else { return 0 }
        return Double(strip.stacking(ofPageAt: index, at: position, leaving: restingIndex))
    }

    /// Where in the strip the Space it last rested on stands.
    private var restingIndex: Int? {
        restingSpaceID.flatMap { strip.spaceIDs.firstIndex(of: $0) }
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot) {
        guard snapshot.order(of: spaces) != nil, snapshot.position.isFinite else { return }
        if snapshot.phase != .idle, landedSpaceID != nil { landedSpaceID = nil }
        // A strip at rest stands exactly on a Space.
        let rounded = snapshot.position.rounded()
        let position =
            snapshot.phase == .idle && abs(snapshot.position - rounded) < 0.001 ? rounded : snapshot.position
        let previous = self.snapshot
        self.snapshot = snapshot
        restsWithoutPager = false
        // A finger or a scroll taking over ends a jump's fade, from the Space
        // it was going to.
        if let jump, snapshot.phase != .idle {
            self.jump = nil
            restingSpaceID = jump.destinationID
        }
        if let previous, !slides, previous.phase == .idle, snapshot.phase == .idle,
            previous.spaceIDs == snapshot.spaceIDs, previous.destinationID != snapshot.destinationID,
            abs(position - self.position) >= 0.5
        {
            fade(from: self.position, to: position, reaching: snapshot.destinationID)
            return
        }
        if self.position != position { self.position = position }
        rest(at: snapshot)
        arrange()
    }

    /// Takes the Space a strip at rest stands on as the one its next fade
    /// leaves.
    private func rest(at snapshot: SpacePagerPresentation.Snapshot) {
        // A jump's fade takes its destination as it ends.
        guard jump == nil, snapshot.phase == .idle, restingSpaceID != snapshot.destinationID else { return }
        restingSpaceID = snapshot.destinationID
    }

    /// Fades the cards from `start` to `end`, where the Space `destinationID`
    /// stands, on the pager's settle curve and timing, for a pager that
    /// jumped there. The fade leaves the Space the strip rested on, which the
    /// destination becomes once it ends.
    private func fade(from start: CGFloat, to end: CGFloat, reaching destinationID: UUID?) {
        jumpCount &+= 1
        let move = Jump(
            settlement: SpacePagerSettlement(startPosition: start, endPosition: end, generation: jumpCount),
            destinationID: destinationID)
        jump = move
        arrange()
        withAnimation(move.settlement.animation, completionCriteria: .logicallyComplete) {
            position = end
        } completion: { [weak self] in
            guard let self, jump == move else { return }
            jump = nil
            restingSpaceID = destinationID
            arrange()
        }
    }

    /// Stands the strip on `spaceID`, for a pager that has published nothing
    /// for these Spaces yet.
    private func rest(on spaceID: UUID?) {
        let index = spaceID.flatMap { id in spaces.firstIndex { $0.id == id } } ?? 0
        let snapshot = SpacePagerPresentation.Snapshot(
            generation: 0, spaceIDs: spaces.map(\.id), position: CGFloat(index), phase: .idle,
            destinationID: spaceID)
        self.snapshot = snapshot
        restsWithoutPager = true
        jump = nil
        if position != CGFloat(index) { position = CGFloat(index) }
        rest(at: snapshot)
        arrange()
    }

    /// Lays the strip out in the order the snapshot runs along, and finds the
    /// cards on show: those the pager passes, and both ends of a jump while
    /// it fades. One that shares its place with the shown Space's, showing
    /// the same page, leaves the page to it.
    private func arrange() {
        guard var snapshot else { return }
        let next = SpacePageStrip(snapshot.order(of: spaces) ?? spaces, shownPins: shownPins)
        if strip != next { strip = next }
        if let jump {
            let move = jump.settlement
            snapshot = SpacePagerPresentation.Snapshot(
                generation: snapshot.generation, spaceIDs: snapshot.spaceIDs, position: move.startPosition,
                phase: .settling, destinationID: snapshot.destinationID, transition: move)
        }
        let pages = strip.spaceIDs.indices.filter { index in
            strip.presentation(at: index, in: snapshot, selectedSpaceID: shownSpaceID) != .inactive
                && !strip.yieldsPlace(at: index, selectedSpaceID: shownSpaceID, in: snapshot)
        }.map { strip.spaceIDs[$0] }
        if pageSpaceIDs != pages { pageSpaceIDs = pages }
    }
}
