import SwiftUI

/// The compact Space picker shared by the live macOS sidebar and setup surfaces.
struct CrestSpaceIconPicker<SegmentContent: View>: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID?
    let selectSpace: (SpaceID) -> Void
    var selectionTint: Color? = nil
    var accessibilityIdentifier: String?
    var moveSpace: ((SpaceID, SpaceID) -> Void)? = nil
    var reorderViewport = CGRect.zero
    var segmentSize = CGSize(
        width: CrestSpaceIconPickerMetrics.segmentWidth,
        height: CrestSpaceIconPickerMetrics.segmentHeight)
    @ViewBuilder let segmentContent: (BrowserSpace) -> SegmentContent

    @State private var reorder = CrestSpacePickerReordering()
    @State private var frames: [SpaceID: CGRect] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                HStack(spacing: 0) {
                    reorderableButton(space)

                    if space.id != spaces.last?.id {
                        Divider()
                            .frame(height: CrestSpaceIconPickerMetrics.dividerHeight)
                    }
                }
                .zIndex(reorder.sourceID == space.id ? 1 : 0)
            }
        }
        .padding(CrestSpaceIconPickerMetrics.trackPadding)
        .background {
            RoundedRectangle(
                cornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
                style: .continuous
            )
            .fill(Color.primary.opacity(CrestSpaceIconPickerMetrics.trackFillOpacity))
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
                style: .continuous
            )
            .strokeBorder(
                Color.primary.opacity(CrestSpaceIconPickerMetrics.trackBorderOpacity),
                lineWidth: CrestLayout.hairline / 2
            )
        }
        .fixedSize(horizontal: true, vertical: false)
        .background {
            #if os(macOS)
                if moveSpace != nil {
                    BrowserSpacePickerAutoscroll(
                        viewport: reorderViewport,
                        pointer: reorder.sourceID == nil ? nil : reorder.pointer
                    ) { offset in
                        guard reorder.sourceID != nil else { return }
                        frames = frames.mapValues { $0.offsetBy(dx: offset, dy: 0) }
                        reorder.contentMoved(by: offset, ids: spaces.map(\.id), frames: frames)
                    }
                }
            #endif
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: spaces.map(\.id))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space")
        .crestAccessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder private func reorderableButton(_ space: BrowserSpace) -> some View {
        if let moveSpace {
            let lifted = reorder.sourceID == space.id
            spaceButton(space)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .global)
                } action: {
                    guard reorder.sourceID == nil else { return }
                    frames[space.id] = $0
                }
                .offset(reorder.offset(for: space.id, ids: spaces.map(\.id), frames: frames))
                .scaleEffect(lifted ? 1.08 : 1)
                .shadow(color: .black.opacity(lifted ? 0.25 : 0), radius: 4, y: 2)
                .animation(
                    reduceMotion || lifted ? nil : CrestMotion.dragSource,
                    value: reorder.targetID
                )
                .modifier(
                    BrowserSidebarReorderLiftGesture { phase in
                        switch phase {
                        case .moved(let start, let pointer):
                            reorder.update(
                                source: space.id, ids: spaces.map(\.id), frames: frames, start: start, pointer: pointer,
                                viewport: reorderViewport)
                        case .released:
                            guard reorder.sourceID == space.id else { return }
                            if let move = reorder.end() { moveSpace(move.source, move.target) }
                        }
                    }
                )
                #if os(macOS)
                    .accessibilityHint("Select this Space, or drag to reorder")
                #else
                    .accessibilityHint("Touch and hold for options to reorder Spaces")
                #endif
                .contextMenu {
                    if let index = spaces.firstIndex(where: { $0.id == space.id }) {
                        Button("Move Left", systemImage: "arrow.left") {
                            moveSpace(space.id, spaces[index - 1].id)
                        }
                        .disabled(index == 0)
                        Button("Move Right", systemImage: "arrow.right") {
                            moveSpace(space.id, spaces[index + 1].id)
                        }
                        .disabled(index == spaces.count - 1)
                    }
                }
        } else {
            spaceButton(space)
        }
    }

    private func spaceButton(_ space: BrowserSpace) -> some View {
        let isSelected = space.id == selectedSpaceID
        let tint = selectionTint ?? space.branding.primaryColor.color
        let accessibilityValue = accessibilityValue(
            isSelected: isSelected,
            requiresAuthentication: space.accessPolicy.requiresAuthentication
        )

        return Button {
            selectSpace(space.id)
        } label: {
            segmentContent(space)
                .frame(
                    width: segmentSize.width,
                    height: segmentSize.height
                )
                .contentShape(.rect)
                .background {
                    if isSelected {
                        RoundedRectangle(
                            cornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
                            style: .continuous
                        )
                        .fill(tint.opacity(CrestSpaceIconPickerMetrics.selectionFillOpacity))
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: CrestSpaceIconPickerMetrics.cornerRadius,
                                style: .continuous
                            )
                            .strokeBorder(tint, lineWidth: CrestLayout.hairline)
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: space.name))
        .accessibilityValue(Text(accessibilityValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(space.name)
        .id(space.id)
    }

    private func accessibilityValue(
        isSelected: Bool,
        requiresAuthentication: Bool
    ) -> LocalizedStringResource {
        switch (isSelected, requiresAuthentication) {
        case (true, true):
            "Selected, Private Space"
        case (true, false):
            "Selected, Open Space"
        case (false, true):
            "Private Space"
        case (false, false):
            "Open Space"
        }
    }
}
