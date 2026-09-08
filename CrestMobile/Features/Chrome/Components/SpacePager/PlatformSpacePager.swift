import SwiftUI

/// A fixed transition between Spaces. Nearby sidebars retain their vertical
/// scroll state; horizontal input requests a step instead of moving a scroll strip.
struct PlatformSpacePager<Content: View>: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let isInteractionLocked: Bool
    let selectSpace: (SpaceID) -> SpaceID
    let settledSpace: (SpaceID) -> Void
    @ViewBuilder let content: (BrowserSpace, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var transition: SpacePagerTransition
    @State private var retainedSpaceIDs: Set<SpaceID>
    @State private var incomingDirection: CGFloat = 1

    init(
        spaces: [BrowserSpace],
        selectedSpaceID: SpaceID,
        isInteractionLocked: Bool = false,
        selectSpace: @escaping (SpaceID) -> SpaceID,
        settledSpace: @escaping (SpaceID) -> Void = { _ in },
        @ViewBuilder content: @escaping (BrowserSpace, Bool) -> Content
    ) {
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.isInteractionLocked = isInteractionLocked
        self.selectSpace = selectSpace
        self.settledSpace = settledSpace
        self.content = content
        _transition = State(initialValue: SpacePagerTransition(spaceID: selectedSpaceID))
        _retainedSpaceIDs = State(initialValue: Self.neighbors(of: selectedSpaceID, in: spaces))
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(spaces) { space in
                    if retainedSpaceIDs.contains(space.id) {
                        content(space, space.id == selectedSpaceID)
                            .id(BrowserSpaceRuntimeAssignment(space: space))
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(x: horizontalOffset(for: space.id, width: geometry.size.width))
                            .transition(
                                space.id == selectedSpaceID
                                    ? .asymmetric(
                                        insertion: .offset(x: geometry.size.width * incomingDirection),
                                        removal: .identity
                                    ) : .identity
                            )
                            .allowsHitTesting(space.id == selectedSpaceID)
                            .accessibilityHidden(space.id != selectedSpaceID)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .modifier(
            PlatformSpaceGestureModifier(
                isEnabled: BrowserSpacePagerPolicy.canSwitchSpaces(
                    spaceCount: spaces.count,
                    isInteractionLocked: isInteractionLocked
                ),
                onStep: requestStep
            )
        )
        .task(id: transition.isAnimating ? nil : transition.generation) {
            guard !transition.isAnimating, !isInteractionLocked else { return }
            let generation = transition.generation
            // Let the selected page settle before building a new offscreen
            // neighbor. A warm adjacent gesture moves already prepared views.
            await Task.yield()
            guard !Task.isCancelled, transition.generation == generation,
                !transition.isAnimating
            else { return }
            let required = Self.neighbors(of: selectedSpaceID, in: spaces)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                retainedSpaceIDs = retainedPages(required: required)
            }
        }
        .onChange(of: selectedSpaceID) { _, spaceID in
            present(spaceID)
        }
        .onChange(of: spaces.map(BrowserSpaceRuntimeAssignment.init(space:))) {
            cancelMotion()
        }
        .onChange(of: isInteractionLocked) {
            cancelMotion()
        }
        .onChange(of: reduceMotion) {
            cancelMotion()
        }
        .onDisappear {
            cancelMotion()
        }
    }

    private func requestStep(_ direction: BrowserSpaceSwipeDirection) {
        guard !isInteractionLocked, let step = transition.request(direction) else { return }
        guard
            let spaceID = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                direction: step == .next ? .next : .previous
            )
        else { return }
        _ = selectSpace(spaceID)
    }

    private func present(_ spaceID: SpaceID) {
        guard spaces.contains(where: { $0.id == spaceID }) else {
            cancelMotion()
            return
        }
        // Do not construct the next offscreen neighbor on the gesture path.
        // One spare sidebar avoids destroying/rebuilding the same neighbors
        // while the user moves back and forth across an adjacent pair.
        let origin = spaces.firstIndex(where: { $0.id == transition.spaceID }) ?? 0
        let destination = spaces.firstIndex(where: { $0.id == spaceID }) ?? origin
        // Intermediate cached pages must not travel across the viewport during
        // a direct jump. Only the outgoing and incoming pages cross its edge.
        let intermediate = Set(
            spaces.indices.filter { $0 > min(origin, destination) && $0 < max(origin, destination) }
                .map { spaces[$0].id }
        )
        let retained = retainedPages(required: [spaceID, transition.spaceID], excluding: intermediate)
        let direction: CGFloat = destination >= origin ? 1 : -1
        let animation =
            isInteractionLocked
            ? nil
            : BrowserVisualAccessibilityPolicy.animation(
                CrestMotion.spaceSwipe, reduceMotion: reduceMotion
            )
        let generation = transition.generation &+ 1
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            incomingDirection = direction * (layoutDirection == .rightToLeft ? -1 : 1)
            retainedSpaceIDs = retained
            _ = transition.begin(spaceID: spaceID)
        } completion: {
            guard transition.generation == generation, selectedSpaceID == spaceID else { return }
            let pendingStep = transition.finish(generation: generation)
            settledSpace(spaceID)
            if let pendingStep { requestStep(pendingStep) }
        }
    }

    private func cancelMotion() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            transition.cancel(spaceID: selectedSpaceID)
            // A drag lock or Reduce Motion change should not discard a warm
            // neighbor or synchronously build a new one. Preparation resumes
            // after cancellation when the pager is unlocked.
            retainedSpaceIDs = retainedPages(required: [selectedSpaceID])
        }
    }

    private func horizontalOffset(for spaceID: SpaceID, width: CGFloat) -> CGFloat {
        guard let current = spaces.firstIndex(where: { $0.id == transition.spaceID }),
            let index = spaces.firstIndex(where: { $0.id == spaceID })
        else { return 0 }
        let direction = layoutDirection == .rightToLeft ? -1.0 : 1.0
        return CGFloat(min(1, max(-1, index - current))) * width * direction
    }

    private func retainedPages(required: Set<SpaceID>, excluding: Set<SpaceID> = []) -> Set<SpaceID> {
        let destination = spaces.firstIndex(where: { $0.id == selectedSpaceID }) ?? 0
        let spare = spaces.enumerated()
            .filter {
                retainedSpaceIDs.contains($0.element.id)
                    && !required.contains($0.element.id) && !excluding.contains($0.element.id)
            }
            .sorted { abs($0.offset - destination) < abs($1.offset - destination) }
            .prefix(max(0, 4 - required.count))
            .map(\.element.id)
        return required.union(spare)
    }

    private static func neighbors(of spaceID: SpaceID, in spaces: [BrowserSpace]) -> Set<SpaceID> {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }) else { return [] }
        return Set(spaces[max(0, index - 1)...min(spaces.count - 1, index + 1)].map(\.id))
    }
}
