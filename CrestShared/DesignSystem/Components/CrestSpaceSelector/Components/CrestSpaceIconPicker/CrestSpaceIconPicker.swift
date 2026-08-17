import SwiftUI

/// The compact Space picker shared by the live macOS sidebar and setup surfaces.
struct CrestSpaceIconPicker<SegmentContent: View>: View {
    let spaces: [BrowserSpace]
    let selectedSpaceID: SpaceID?
    let selectSpace: (SpaceID) -> Void
    var selectionTint: Color? = nil
    var accessibilityIdentifier: String?
    @ViewBuilder let segmentContent: (BrowserSpace) -> SegmentContent

    var body: some View {
        HStack(spacing: 0) {
            ForEach(spaces) { space in
                HStack(spacing: 0) {
                    spaceButton(space)

                    if space.id != spaces.last?.id {
                        Divider()
                            .frame(height: CrestSpaceIconPickerMetrics.dividerHeight)
                    }
                }
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space")
        .crestAccessibilityIdentifier(accessibilityIdentifier)
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
                    width: CrestSpaceIconPickerMetrics.segmentWidth,
                    height: CrestSpaceIconPickerMetrics.segmentHeight
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
