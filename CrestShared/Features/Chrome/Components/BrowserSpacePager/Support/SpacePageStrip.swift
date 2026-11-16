import SwiftUI

// MARK: - Types

/// Presentation is independent of selection: both sides of a slide need their
/// content, but neither may own input until the selected page has settled.
enum SpaceContentPresentation {
    case inactive
    case preview
    case interactive
}

extension EnvironmentValues {
    @Entry var spaceContentPresentation = SpaceContentPresentation.interactive
}

/// A window's Space pages side by side, as a Space pager moves them, on every
/// platform: the order they run along, the places neighbouring Spaces that
/// show one page share, where each page stands at a position, or how opaque
/// it is where pages fade rather than slide, which pages the page area keeps,
/// and what each of them shows.
///
/// Each platform's page area only hosts the pages and moves them, the Mac's
/// with Core Animation and a touch device's with SwiftUI; this decides where
/// they go and how they look at every position the pager passes through, so
/// both follow the pager alike, a finger and a release.
struct SpacePageStrip: Equatable {
    // MARK: - Static Variables

    /// The most pages a page area keeps at once.
    static let capacity = 4

    // MARK: - Variables

    /// The Spaces in the order the strip runs along.
    let spaceIDs: [UUID]
    /// The places where a Space and the next one show the same page, a
    /// pinned tab their group shares, by the first one's index. The two count
    /// as one place, so moving between them moves no page.
    let sharedPlaces: Set<Int>

    // MARK: - Initializers

    /// Lays `spaces` out in their order, where `shownPins` is the pinned tab
    /// each Space shows, for the Spaces that show one.
    @MainActor
    init(_ spaces: [SpaceModel], shownPins: [UUID: UUID]) {
        spaceIDs = spaces.map(\.id)
        sharedPlaces = Set(
            spaces.indices.dropLast().filter { index in
                let (space, next) = (spaces[index], spaces[index + 1])
                return space.profileID == next.profileID && shownPins[space.id] != nil
                    && shownPins[space.id] == shownPins[next.id]
            })
    }

    // MARK: - Actions - Places

    /// Where the strip stands at `position` when neighbouring Spaces that
    /// show the same page count as one place. A place beyond the ends, which
    /// a slide around them reaches, keeps its distance from the end.
    func place(_ position: CGFloat) -> CGFloat {
        guard !sharedPlaces.isEmpty, !spaceIDs.isEmpty else { return position }
        let clamped = min(max(position, 0), CGFloat(spaceIDs.count - 1))
        let lower = Int(clamped.rounded(.down))
        var reached = CGFloat(lower - sharedPlaces.count { $0 < lower })
        if !sharedPlaces.contains(lower) { reached += clamped - CGFloat(lower) }
        return reached + position - clamped
    }

    /// How many pages toward the trailing edge the page at `index` stands
    /// while the strip shows `position`, placed around the ends as near
    /// `reference`: a slide keeps each page where it began, so none switches
    /// ends partway. A page at the strip's own place, as one that shares it
    /// with its neighbour is, stays where it is.
    func offset(ofPageAt index: Int, at position: CGFloat, placedNear reference: CGFloat? = nil) -> CGFloat {
        guard place(CGFloat(index)) != place(position) else { return 0 }
        let placed = SpacePagerInterpolation.index(index, near: reference ?? position, count: spaceIDs.count)
        return place(CGFloat(placed)) - place(position)
    }

    // MARK: - Actions - Fading

    /// How opaque the page at `index` is, where pages fade rather than slide,
    /// while the strip shows `position` on its way from the page at `origin`,
    /// where it last rested: the page at the position whole, and between two
    /// pages, the one the strip moves toward fading in over the one it
    /// leaves. The page it leaves stays whole until halfway, so the first
    /// half is a true mix of the two, and then fades away under the other,
    /// letting at most an eighth of what lies behind show through in the
    /// second half. Kept whole to the end, it would show through a page with
    /// clear parts, as a Start Page has, and then vanish at once. A move
    /// either way looks the same. Neighbouring Spaces that show one page
    /// count as one place, so moving between them fades nothing.
    func opacity(
        ofPageAt index: Int, at position: CGFloat, leaving origin: Int?, placedNear reference: CGFloat? = nil
    ) -> CGFloat {
        let distance = abs(offset(ofPageAt: index, at: position, placedNear: reference))
        guard distance < 1 else { return 0 }
        return leaves(index, from: origin, at: position, placedNear: reference)
            ? min(1, 2 * (1 - distance)) : 1 - distance
    }

    /// Where the page at `index` stacks while pages fade from the page at
    /// `origin`: the page the strip leaves beneath, and the others above it,
    /// nearest on top.
    func stacking(
        ofPageAt index: Int, at position: CGFloat, leaving origin: Int?, placedNear reference: CGFloat? = nil
    ) -> CGFloat {
        guard !leaves(index, from: origin, at: position, placedNear: reference) else { return 0 }
        return 2 - abs(offset(ofPageAt: index, at: position, placedNear: reference))
    }

    /// Whether the page at `index` is the one the strip leaves on its way
    /// from `origin`: that page, or, with no origin known, the page behind
    /// the position.
    private func leaves(_ index: Int, from origin: Int?, at position: CGFloat, placedNear reference: CGFloat?) -> Bool {
        guard let origin else { return offset(ofPageAt: index, at: position, placedNear: reference) < 0 }
        return place(CGFloat(index)) == place(CGFloat(origin))
    }

    // MARK: - Actions - Sharing

    /// Whether the page at `index` shares its place with the selected
    /// Space's while the strip moves. Only the selected Space draws that page
    /// then, as it held it before the move.
    func yieldsPlace(at index: Int, selectedSpaceID: UUID?, in snapshot: SpacePagerPresentation.Snapshot?) -> Bool {
        guard let snapshot, snapshot.phase != .idle, !sharedPlaces.isEmpty,
            let selected = spaceIDs.firstIndex(where: { $0 == selectedSpaceID }), selected != index
        else { return false }
        return place(CGFloat(index)) == place(CGFloat(selected))
    }

    // MARK: - Actions - Pages

    /// The pages a page area keeps at `position`, by index: those in view,
    /// the one the strip goes to, a selection made mid-move, and where it
    /// `keepsNeighbors`, the pages either side and the pages it `keeps`
    /// already, nearest first, up to `capacity`.
    func keptIndices(
        at position: CGFloat, destinationID: UUID?, selectedSpaceID: UUID?, isMoving: Bool, keepsNeighbors: Bool,
        keeps: [Int] = []
    ) -> Set<Int> {
        guard !spaceIDs.isEmpty else { return [] }
        let center = min(spaceIDs.count - 1, max(0, Int(position.rounded())))
        let target = destinationID.flatMap { id in spaceIDs.firstIndex(of: id) } ?? center
        var visible = Set([Int(position.rounded(.down)), Int(position.rounded(.up)), target])
        if isMoving, let selected = spaceIDs.firstIndex(where: { $0 == selectedSpaceID }) {
            // A selection made mid-slide is where the slide goes next.
            visible.insert(selected)
        }
        var indices = visible.filter(spaceIDs.indices.contains)
        guard keepsNeighbors else { return indices }
        for index in [target - 1, target + 1, center - 1, center + 1]
        where indices.count < Self.capacity && spaceIDs.indices.contains(index) {
            indices.insert(index)
        }
        for index in keeps.sorted(by: { abs($0 - target) < abs($1 - target) }) where indices.count < Self.capacity {
            indices.insert(index)
        }
        return indices
    }

    /// What the page at `index` shows at `snapshot`, where `selectedSpaceID`
    /// is the Space the window shows: the shown page at rest takes input, the
    /// pages a move passes through or goes to are previews, and the rest
    /// show nothing.
    func presentation(
        at index: Int, in snapshot: SpacePagerPresentation.Snapshot?, selectedSpaceID: UUID?
    ) -> SpaceContentPresentation {
        guard let snapshot, spaceIDs.indices.contains(index) else { return .inactive }
        let id = spaceIDs[index]
        if snapshot.phase == .idle {
            guard id == snapshot.destinationID else { return .inactive }
            return id == selectedSpaceID ? .interactive : .preview
        }
        // Keep the complete release path alive even as position samples
        // advance or a reversal carries the strip through an intermediate
        // Space.
        let start = snapshot.transition?.startPosition ?? snapshot.position
        let end = snapshot.transition?.endPosition ?? snapshot.position
        let visible = Int(min(start, end).rounded(.down))...Int(max(start, end).rounded(.up))
        // A Space selected mid-slide is admitted with that selection, so the
        // slide carrying on to it doesn't wait on its first layout.
        return visible.contains(index) || id == snapshot.destinationID || id == selectedSpaceID
            ? .preview : .inactive
    }
}
