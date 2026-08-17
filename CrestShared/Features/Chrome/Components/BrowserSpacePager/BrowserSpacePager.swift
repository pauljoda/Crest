import SwiftUI

/// A native, horizontally paged Space strip. Every Space keeps stable identity in
/// the scroll content while the lazy stack materializes only the pages near the
/// viewport, so an in-progress gesture still exposes the neighboring sidebar.
struct BrowserSpacePager<Content: View>: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID
    let isInteractionLocked: Bool
    let selectSpace: (SpaceID) -> Void
    let settledSpace: (SpaceID) -> Void
    @ViewBuilder let content: (BrowserSpace, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleSpaceID: SpaceID?
    @State private var recenterRevision: UInt = 0

    init(
        spaces: [BrowserSpace],
        selectedSpaceID: SpaceID,
        isInteractionLocked: Bool = false,
        selectSpace: @escaping (SpaceID) -> Void,
        settledSpace: @escaping (SpaceID) -> Void = { _ in },
        @ViewBuilder content: @escaping (BrowserSpace, Bool) -> Content
    ) {
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.isInteractionLocked = isInteractionLocked
        self.selectSpace = selectSpace
        self.settledSpace = settledSpace
        self.content = content
        _visibleSpaceID = State(initialValue: selectedSpaceID)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(
                .horizontal,
                showsIndicators: BrowserSpacePagerPolicy.showsScrollIndicators
            ) {
                LazyHStack(spacing: 0) {
                    ForEach(spaces) { space in
                        content(space, space.id == selectedSpaceID)
                            .id(BrowserSpaceRuntimeAssignment(space: space))
                            .containerRelativeFrame(.horizontal)
                            .id(space.id)
                    }
                }
                .scrollTargetLayout()
                .background(BrowserPlatformHorizontalScrollerSuppressor())
            }
            .scrollIndicators(
                BrowserSpacePagerPolicy.scrollIndicatorVisibility,
                axes: .horizontal
            )
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $visibleSpaceID, anchor: .center)
            .scrollDisabled(
                !BrowserSpacePagerPolicy.isScrollEnabled(
                    spaceCount: spaces.count,
                    isInteractionLocked: isInteractionLocked
                )
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Spaces")
            .accessibilityValue(
                BrowserChromeAccessibility.spaceValue(
                    spaces: spaces,
                    selectedSpaceID: selectedSpaceID
                )
            )
            .accessibilityIdentifier("space-pager")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    adjustSpaceForAccessibility(.next)
                case .decrement:
                    adjustSpaceForAccessibility(.previous)
                @unknown default:
                    break
                }
            }
            .accessibilityAction(named: "Previous Space") {
                adjustSpaceForAccessibility(.previous)
            }
            .accessibilityAction(named: "Next Space") {
                adjustSpaceForAccessibility(.next)
            }
            .onChange(of: visibleSpaceID) { _, spaceID in
                guard let spaceID,
                    spaceID != selectedSpaceID,
                    spaces.contains(where: { $0.id == spaceID })
                else { return }
                selectSpace(spaceID)
            }
            .onChange(of: selectedSpaceID, initial: true) { _, spaceID in
                recenterRevision &+= 1
                guard spaces.contains(where: { $0.id == spaceID }) else { return }
                guard visibleSpaceID != spaceID else { return }
                withAnimation(
                    BrowserVisualAccessibilityPolicy.animation(
                        CrestMotion.spaceSwipe,
                        reduceMotion: reduceMotion
                    )
                ) {
                    visibleSpaceID = spaceID
                } completion: {
                    guard visibleSpaceID == spaceID else { return }
                    settledSpace(spaceID)
                }
            }
            .onChange(of: isInteractionLocked) { wasLocked, isLocked in
                recenterRevision &+= 1
                guard
                    BrowserSpacePagerPolicy.shouldRecenter(
                        wasInteractionLocked: wasLocked,
                        isInteractionLocked: isLocked
                    )
                else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    visibleSpaceID = selectedSpaceID
                    scrollProxy.scrollTo(selectedSpaceID, anchor: .center)
                }
                guard !isLocked else { return }
                let request = BrowserSpacePagerRecenterRequest(
                    revision: recenterRevision,
                    spaceID: selectedSpaceID
                )
                DispatchQueue.main.async {
                    guard
                        request.isCurrent(
                            revision: recenterRevision,
                            selectedSpaceID: selectedSpaceID,
                            isInteractionLocked: isInteractionLocked
                        )
                    else { return }
                    var settledTransaction = Transaction()
                    settledTransaction.disablesAnimations = true
                    withTransaction(settledTransaction) {
                        visibleSpaceID = request.spaceID
                        scrollProxy.scrollTo(request.spaceID, anchor: .center)
                    }
                }
            }
            .onScrollPhaseChange { _, phase in
                guard !phase.isScrolling, let visibleSpaceID else { return }
                settledSpace(visibleSpaceID)
            }
        }
    }

    private func adjustSpaceForAccessibility(
        _ direction: BrowserChromeAccessibilityDirection
    ) {
        guard
            let spaceID = BrowserChromeAccessibility.adjacentSpaceID(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                direction: direction
            )
        else { return }
        selectSpace(spaceID)
    }
}
