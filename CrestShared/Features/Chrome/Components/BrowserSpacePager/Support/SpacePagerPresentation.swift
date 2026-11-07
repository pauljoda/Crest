import SwiftUI

extension EnvironmentValues {
    @Entry var spacePagerPresentation: SpacePagerPresentation? = nil
    /// Retained content can render before its Space owns input or focus.
    @Entry var spaceContentIsInteractive = true
}

/// A view-only connection between native page motion, backgrounds, and icons.
/// It deliberately does not participate in Observation: progress updates only
/// the native presentation leaf, never the browser selection or sidebar rows.
@MainActor
final class SpacePagerPresentation {
    // MARK: - Types

    enum Phase: Equatable {
        case idle
        case tracking
        case settling
    }

    struct Snapshot: Equatable {
        let generation: UInt
        /// The order the position runs along: the Spaces in their order, or,
        /// while a slide jumps to a Space further away than next door, that
        /// order with the destination moved beside the Space the slide leaves.
        let spaceIDs: [UUID]
        /// Fractional index in `spaceIDs`, independent of layout direction.
        let position: CGFloat
        let phase: Phase
        let destinationID: UUID?
        var transition: SpacePagerSettlement? = nil

        /// `elements` in the order the position runs along, matched by `id`,
        /// or nil when the snapshot is of other Spaces.
        func order<Element>(of elements: [Element], id: (Element) -> UUID) -> [Element]? {
            guard elements.count == spaceIDs.count else { return nil }
            let byID = Dictionary(elements.map { (id($0), $0) }, uniquingKeysWith: { first, _ in first })
            let ordered = spaceIDs.compactMap { byID[$0] }
            return ordered.count == spaceIDs.count ? ordered : nil
        }

        /// `spaces` in the order the position runs along, or nil when the
        /// snapshot is of other Spaces.
        func order(of spaces: [SpaceModel]) -> [SpaceModel]? {
            order(of: spaces, id: \.id)
        }

        /// Where `position`, along the order the snapshot runs along, falls
        /// among `spaceIDs` in their own order: between the two Spaces either
        /// side of it, wherever those stand there. A jump moves the pager
        /// along another order while a Space picker's icons keep their places.
        func place(_ position: CGFloat, among spaceIDs: [UUID]) -> CGFloat {
            guard self.spaceIDs != spaceIDs,
                let sample = SpacePagerInterpolation(position: position, count: self.spaceIDs.count),
                let lower = spaceIDs.firstIndex(of: self.spaceIDs[sample.lower]),
                let upper = spaceIDs.firstIndex(of: self.spaceIDs[sample.upper])
            else { return position }
            return CGFloat(lower) + CGFloat(upper - lower) * sample.fraction
        }
    }

    // MARK: - Variables

    private(set) var snapshot: Snapshot?
    /// Fixed controls above the moving page remain part of its gesture region.
    var gestureTopInset: CGFloat = 0
    private struct Observer {
        weak var owner: AnyObject?
        let receive: (Snapshot) -> Void
    }
    private var observers: [ObjectIdentifier: Observer] = [:]

    // MARK: - Actions - Observation

    func publish(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        observers = observers.filter { $0.value.owner != nil }
        for observer in observers.values {
            if observer.owner != nil { observer.receive(snapshot) }
        }
    }

    func observe(owner: AnyObject, receive: @escaping (Snapshot) -> Void) {
        observers[ObjectIdentifier(owner)] = Observer(owner: owner, receive: receive)
        if let snapshot { receive(snapshot) }
    }

    func removeObserver(owner: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(owner))
    }

    // MARK: - Actions - Order

    /// The order a slide from `origin` to `target` runs along when they lie
    /// further apart than next door: `elements` with `target` moved beside
    /// `origin`, on the side it lies. The slide then moves one page, as it
    /// does between neighbours, and `origin` keeps its place, so the slide
    /// starts where the strip rests. Nil where they are next door already or
    /// either is missing.
    static func jumpOrder<Element>(
        _ elements: [Element], from origin: UUID, to target: UUID, id: (Element) -> UUID
    ) -> [Element]? {
        guard let originIndex = elements.firstIndex(where: { id($0) == origin }),
            let targetIndex = elements.firstIndex(where: { id($0) == target }),
            abs(targetIndex - originIndex) > 1
        else { return nil }
        var order = elements
        let moved = order.remove(at: targetIndex)
        // Removing a Space before the origin moves the origin one place back.
        let origin = targetIndex < originIndex ? originIndex - 1 : originIndex
        order.insert(moved, at: targetIndex < originIndex ? origin : origin + 1)
        return order
    }
}
