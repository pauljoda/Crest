import SwiftUI

/// A horizontal rail of crest-badged Space chips, ending in a dashed add chip.
struct CrestSpaceChipRail: View {
    let spaces: [CrestSpaceIdentity]
    @Binding var selection: SpaceID?
    var add: CrestSpaceChipAddAction?
    var commands: ((CrestSpaceIdentity) -> [CrestSpaceChipCommand])?
    var accessibilityIdentifier: String?

    init(
        spaces: [CrestSpaceIdentity],
        selection: Binding<SpaceID?>,
        add: CrestSpaceChipAddAction? = nil,
        commands: ((CrestSpaceIdentity) -> [CrestSpaceChipCommand])? = nil,
        accessibilityIdentifier: String? = nil
    ) {
        self.spaces = spaces
        _selection = selection
        self.add = add
        self.commands = commands
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: CrestSpaceChipMetrics.railSpacing) {
                ForEach(spaces) { identity in
                    chip(identity)
                }

                if let add {
                    addChip(add)
                }
            }
            .padding(.vertical, CrestSpacing.extraExtraSmall)
            .crestCollectionMotion(ids: spaces.map(\.id))
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .crestAccessibilityIdentifier(accessibilityIdentifier)
    }

    private func chip(_ identity: CrestSpaceIdentity) -> some View {
        let isSelected = identity.id == selection
        return Button {
            selection = identity.id
        } label: {
            HStack(spacing: CrestSpaceChipMetrics.contentSpacing) {
                BrowserSpaceSymbolArtwork(
                    space: identity.space,
                    size: CrestSpaceChipMetrics.iconSize,
                    lockSize: CrestSpaceChipMetrics.lockSize
                )
                Text(verbatim: identity.name)
                    .lineLimit(1)
            }
        }
        .buttonStyle(
            CrestSpaceChipStyle(tint: identity.tint, isSelected: isSelected)
        )
        .accessibilityLabel(Text(verbatim: identity.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .crestCollectionItemTransition()
        .modifier(CrestSpaceChipCommands(commands: commands?(identity) ?? []))
    }

    private func addChip(_ add: CrestSpaceChipAddAction) -> some View {
        Button(action: add.perform) {
            HStack(spacing: CrestSpaceChipMetrics.contentSpacing) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                Text(add.title)
                    .lineLimit(1)
            }
        }
        .buttonStyle(CrestSpaceAddChipStyle(tint: addTint))
        .accessibilityLabel(Text(add.title))
        .crestAccessibilityIdentifier(add.accessibilityIdentifier)
    }

    private var addTint: Color {
        spaces.first { $0.id == selection }?.tint ?? CrestBrandTheme.accent
    }
}

#Preview("Space Chip Rail", traits: .sizeThatFitsLayout) {
    @Previewable @State var selection =
        CrestSpaceSelectorPreviewFixture.selectedSpaceID(for: .chips)

    CrestSpaceChipRail(
        spaces: CrestSpaceSelectorPreviewFixture.identities,
        selection: $selection,
        add: CrestSpaceChipAddAction(
            title: "New Space",
            accessibilityIdentifier: "preview-add-space"
        ) {},
        commands: { _ in
            [
                .rename {},
                .customize {},
                .delete {},
            ]
        },
        accessibilityIdentifier: "preview-space-rail"
    )
    .padding()
    .frame(width: 440)
    .environment(\.displayScale, 2)
    .preferredColorScheme(.light)
}

#Preview("Space Chip Rail — Disabled Dark", traits: .sizeThatFitsLayout) {
    @Previewable @State var selection =
        CrestSpaceSelectorPreviewFixture.selectedSpaceID(for: .chips)

    CrestSpaceChipRail(
        spaces: CrestSpaceSelectorPreviewFixture.identities,
        selection: $selection,
        add: CrestSpaceChipAddAction(title: "New Space") {}
    )
    .disabled(true)
    .padding()
    .frame(width: 440)
    .environment(\.displayScale, 2)
    .preferredColorScheme(.dark)
}
