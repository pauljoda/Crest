import CoreGraphics
import Foundation

/// The groups a Space picker outlines around its selection: each run of
/// Spaces that browse with one profile, which is a group's primary followed by
/// its Sub-Spaces. At every position the pager moves through it answers the
/// frame the outline wraps, how strongly it shows and how far the selection
/// sits inside it, so moving into a group grows the outline from the segment
/// to the group, moving within one holds it still, and leaving shrinks it
/// back onto the selection. A picker whose Spaces are all on their own, or
/// all in one group, outlines nothing.
struct SpacePickerGroupOutline: Equatable {
    // MARK: - Types

    /// The outline at one position.
    struct Frame: Equatable {
        let rect: CGRect
        /// 0 where neither neighbour of the position is in a group, 1 where
        /// both are.
        let opacity: CGFloat
        /// How far the selection sits inside the segment it shows.
        let selectionInset: CGFloat
    }

    // MARK: - Variables

    /// Each Space's group, as the first and last index of the group.
    private let groupOf: [ClosedRange<Int>]
    /// Whether any group holds more than one Space and no group holds all.
    let outlinesGroups: Bool

    // MARK: - Initializers

    /// The groups of Spaces listed in order with the profiles `profileIDs`
    /// browse with.
    init(profileIDs: [UUID]) {
        var groups: [ClosedRange<Int>] = []
        var start = 0
        for index in profileIDs.indices
        where index == profileIDs.count - 1 || profileIDs[index + 1] != profileIDs[index] {
            groups.append(start...index)
            start = index + 1
        }
        groupOf = groups.flatMap { group in group.map { _ in group } }
        outlinesGroups = groups.contains { $0.count > 1 } && groups.count > 1
    }

    // MARK: - Actions - Reading

    /// The outline at `position`, where `frames` gives each Space's segment by
    /// index and `inset` is how far a selection sits inside a group's outline;
    /// nil where it shows nothing.
    func frame(at position: CGFloat, frames: (Int) -> CGRect?, inset: CGFloat) -> Frame? {
        guard outlinesGroups, let sample = SpacePagerInterpolation(position: position, count: groupOf.count),
            let lower = wrap(sample.lower, frames: frames), let upper = wrap(sample.upper, frames: frames)
        else { return nil }
        let grouped = (lower: isGrouped(sample.lower) ? 1.0 : 0.0, upper: isGrouped(sample.upper) ? 1.0 : 0.0)
        let opacity = grouped.lower + (grouped.upper - grouped.lower) * sample.fraction
        return Frame(rect: sample.frame(from: lower, to: upper), opacity: opacity, selectionInset: inset * opacity)
    }

    /// What the outline wraps around the Space at `index`: its whole group, or
    /// its own segment when it is on its own.
    private func wrap(_ index: Int, frames: (Int) -> CGRect?) -> CGRect? {
        let group = groupOf[index]
        guard group.count > 1 else { return frames(index) }
        let members = group.compactMap(frames)
        guard members.count == group.count, let first = members.first else { return nil }
        return members.dropFirst().reduce(first) { $0.union($1) }
    }

    /// The index of the primary of the Space at `index`'s group, the Space
    /// that leads it, whose colour the outline wears whichever member is
    /// selected.
    func primary(of index: Int) -> Int { groupOf[index].lowerBound }

    private func isGrouped(_ index: Int) -> Bool { groupOf[index].count > 1 }
}
