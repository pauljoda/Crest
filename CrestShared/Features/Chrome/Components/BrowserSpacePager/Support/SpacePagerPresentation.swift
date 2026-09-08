import SwiftUI

extension EnvironmentValues {
    @Entry var spacePagerPresentation: SpacePagerPresentation? = nil
}

/// A view-only connection between native page motion and the compact icon lane.
/// It deliberately does not participate in Observation: progress updates only
/// the native presentation leaf, never the browser selection or sidebar rows.
@MainActor
final class SpacePagerPresentation {
    enum Phase: Equatable {
        case idle
        case tracking
        case settling
    }

    struct Snapshot: Equatable {
        let generation: UInt
        let spaceIDs: [SpaceID]
        /// Fractional index in semantic Space order, independent of layout direction.
        let position: CGFloat
        let phase: Phase
        let destinationID: SpaceID?
    }

    private(set) var snapshot: Snapshot?
    /// Fixed controls above the moving page remain part of its gesture region.
    var gestureTopInset: CGFloat = 0
    private weak var observer: AnyObject?
    private var receive: ((Snapshot) -> Void)?

    func publish(_ snapshot: Snapshot) {
        self.snapshot = snapshot
        guard observer != nil else {
            receive = nil
            return
        }
        receive?(snapshot)
    }

    func observe(owner: AnyObject, receive: @escaping (Snapshot) -> Void) {
        observer = owner
        self.receive = receive
        if let snapshot { receive(snapshot) }
    }

    func removeObserver(owner: AnyObject) {
        guard observer === owner else { return }
        observer = nil
        receive = nil
    }
}
