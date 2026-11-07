import SwiftUI

@MainActor @Observable
final class SpaceForegroundPresentation {
    // MARK: - Types

    struct Tone: Equatable {
        let id: UUID
        let white: Double
    }

    // MARK: - Variables

    private(set) var position: CGFloat?
    /// The order `position` runs along where it isn't the tones' own: a jump
    /// between Spaces far apart puts the two next door until it ends.
    private(set) var order: [UUID]?
    @ObservationIgnored private var presentation: SpacePagerPresentation?
    @ObservationIgnored private var tones: [Tone] = []
    @ObservationIgnored private var selectedSpaceID: UUID?
    @ObservationIgnored private var activeTransition: SpacePagerSettlement?

    // MARK: - Actions - Presentation

    func connect(_ presentation: SpacePagerPresentation?, tones: [Tone], selectedSpaceID: UUID?) {
        if self.presentation !== presentation { disconnect() }
        self.presentation = presentation
        self.tones = tones
        self.selectedSpaceID = selectedSpaceID
        presentation?.observe(owner: self) { [weak self] in self?.receive($0) }
        if presentation?.snapshot == nil { receive(nil) }
    }

    func disconnect() {
        presentation?.removeObserver(owner: self)
        presentation = nil
        activeTransition = nil
    }

    private func receive(_ snapshot: SpacePagerPresentation.Snapshot?) {
        if let transition = snapshot?.transition, activeTransition == transition { return }
        activeTransition = snapshot?.transition
        let ordered = snapshot?.order(of: tones, id: \.id) != nil
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        if let snapshot, ordered, let transition = snapshot.transition {
            // SwiftUI interpolates this leaf's position, including any crossed
            // color boundary, with the pager's single release curve. Do not
            // restart it from main-thread display-link samples. A jump's
            // order keeps the Space it leaves in its place, so the tones
            // rearrange under the position without a visible change.
            withAnimation(transition.animation) {
                arrange(snapshot.spaceIDs)
                position = transition.endPosition
            }
            return
        }
        let value: CGFloat
        if let snapshot, !tones.isEmpty, ordered, snapshot.position.isFinite {
            value = snapshot.position
        } else {
            value = CGFloat(tones.firstIndex { $0.id == selectedSpaceID } ?? 0)
        }
        withTransaction(transaction) {
            arrange(ordered ? snapshot?.spaceIDs : nil)
            position = value
        }
    }

    /// Follows `spaceIDs` as the order the position runs along, kept only
    /// where it differs from the tones' own.
    private func arrange(_ spaceIDs: [UUID]?) {
        let order = spaceIDs == tones.map(\.id) ? nil : spaceIDs
        if self.order != order { self.order = order }
    }

    // MARK: - Actions - Tone

    static func white(at position: CGFloat, tones: [Tone]) -> Double {
        guard let sample = SpacePagerInterpolation(position: position, count: tones.count) else { return 1 }
        let start = tones[sample.lower].white
        return start + (tones[sample.upper].white - start) * Double(sample.fraction)
    }
}
