import SwiftUI

/// Touch follows the native scroll view continuously. The shared sidebar still
/// owns selection and page activation; neither is changed for every drag frame.
/// Only a scroll a person drives settles on another Space: a hardware keyboard's
/// focus also scrolls this view, and the pager then returns to the selected one.
/// A Space chosen further away than next door scrolls in as a neighbour does:
/// the strip puts it next door until the scroll comes to rest.
struct PlatformSpacePager<Content: View>: View {
    // MARK: - Variables

    let spaces: [SpaceModel]
    let selectedSpaceID: UUID
    let isInteractionLocked: Bool
    let selectSpace: (UUID) -> UUID
    @ViewBuilder let content: (SpaceModel, Bool) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.spacePagerPresentation) private var presentation
    @State private var progress = TouchSpacePagerProgress()
    @State private var visibleSpaceID: UUID?
    /// The order the strip runs along while it scrolls to a Space further
    /// away than next door, or nil for the Spaces' own order.
    @State private var jumpOrder: [UUID]?
    /// Whether a jump has just come to rest, and the strip taking the Spaces'
    /// own order again has to bring the Space it reached back on screen.
    @State private var isEndingJump = false

    /// The Spaces in the order the strip runs along.
    private var strip: [SpaceModel] {
        guard let jumpOrder else { return spaces }
        let byID = Dictionary(spaces.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = jumpOrder.compactMap { byID[$0] }
        return ordered.count == spaces.count ? ordered : spaces
    }

    // MARK: - Initializers

    init(
        spaces: [SpaceModel],
        selectedSpaceID: UUID,
        isInteractionLocked: Bool = false,
        selectSpace: @escaping (UUID) -> UUID,
        @ViewBuilder content: @escaping (SpaceModel, Bool) -> Content
    ) {
        self.spaces = spaces
        self.selectedSpaceID = selectedSpaceID
        self.isInteractionLocked = isInteractionLocked
        self.selectSpace = selectSpace
        self.content = content
        _visibleSpaceID = State(initialValue: selectedSpaceID)
    }

    // MARK: - Actions - Presentation

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(strip) { space in
                            // A Space keeps its page when it joins or leaves a group.
                            content(space, space.id == selectedSpaceID)
                                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .top)
                                .id(space.id)
                                .allowsHitTesting(space.id == selectedSpaceID)
                                .accessibilityHidden(space.id != selectedSpaceID)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.never, axes: .horizontal)
                .scrollClipDisabled()
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $visibleSpaceID, anchor: .center)
                .scrollDisabled(isInteractionLocked)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.containerSize.width > 0
                        ? geometry.contentOffset.x / geometry.containerSize.width : 0
                } action: { _, position in
                    progress.update(position: position, ids: strip.map(\.id), presentation: presentation)
                }
                .onScrollPhaseChange { _, phase in
                    progress.update(phase: phase, ids: strip.map(\.id), presentation: presentation)
                    guard phase == .idle else { return }
                    endJump()
                    if progress.isPersonDriven {
                        commitVisibleSpace()
                    } else {
                        show(selectedSpaceID)
                    }
                }
                .onChange(of: selectedSpaceID) { _, spaceID in
                    show(spaceID)
                }
                .onChange(of: jumpOrder) { _, _ in
                    // The Space a jump reached stands elsewhere in the
                    // Spaces' own order, which the strip takes again here.
                    guard isEndingJump else { return }
                    isEndingJump = false
                    guard let visibleSpaceID else { return }
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { proxy.scrollTo(visibleSpaceID, anchor: .center) }
                }
                .onChange(of: isInteractionLocked) { _, _ in
                    recenter(using: proxy)
                }
                .onChange(of: spaces.map(BrowserSpaceRuntimeAssignment.init(space:))) {
                    recenter(using: proxy)
                }
                // The offset is kept in points and starts at the first Space:
                // a pager that appears at its full width, as the sidebar does
                // when the window moves to a larger display, or one given a
                // new width, would otherwise show another Space.
                .onChange(of: viewport.size.width, initial: true) {
                    recenter(using: proxy)
                }
            }
            // The fixed top chrome stays clear. Rows may continue beneath the
            // bottom glass controls, whose safe-area inset still keeps the
            // final tab reachable above them when scrolled to the end.
            .mask(alignment: .top) {
                Rectangle().padding(.bottom, -viewport.safeAreaInsets.bottom)
            }
        }
    }

    // MARK: - Actions - Selection

    private func commitVisibleSpace() {
        guard !isInteractionLocked, let spaceID = visibleSpaceID,
            spaces.contains(where: { $0.id == spaceID })
        else { return }
        let accepted = selectSpace(spaceID)
        if accepted != spaceID { visibleSpaceID = accepted }
    }

    private func show(_ spaceID: UUID) {
        guard visibleSpaceID != spaceID else { return }
        if !reduceMotion, let visibleSpaceID {
            // The Space on show keeps its place in the jump's order, so the
            // strip doesn't move until the scroll below begins. A neighbour
            // takes the Spaces' own order.
            let order = SpacePagerPresentation.jumpOrder(spaces, from: visibleSpaceID, to: spaceID, id: \.id)
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { jumpOrder = order?.map(\.id) }
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
            visibleSpaceID = spaceID
        }
    }

    /// Puts the strip back in the Spaces' own order once a jump comes to
    /// rest.
    private func endJump() {
        guard jumpOrder != nil else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isEndingJump = true
            jumpOrder = nil
        }
    }

    private func recenter(using proxy: ScrollViewProxy) {
        guard spaces.contains(where: { $0.id == selectedSpaceID }) else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            jumpOrder = nil
            visibleSpaceID = selectedSpaceID
            proxy.scrollTo(selectedSpaceID, anchor: .center)
        }
    }
}
