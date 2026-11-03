#if os(iOS)
    import SwiftUI

    /// Uses the live sidebar's track, artwork, and overflow controls. The host owns
    /// selection and ordering, whether it is editing the read model's Spaces or a
    /// setup draft.
    struct BrowserSpaceCustomizationPicker: View {
        // MARK: - Variables

        let spaces: [BrowserSpaceIdentity]
        let selectedSpaceID: UUID
        let selectSpace: (UUID) -> Void
        let moveSpace: (UUID, UUID) -> Void
        let addSpace: () -> Void

        // MARK: - Initializers

        init(
            spaces: [some BrowserSpaceIdentifying],
            selectedSpaceID: UUID,
            selectSpace: @escaping (UUID) -> Void,
            moveSpace: @escaping (UUID, UUID) -> Void,
            addSpace: @escaping () -> Void
        ) {
            self.spaces = spaces.map(\.identity)
            self.selectedSpaceID = selectedSpaceID
            self.selectSpace = selectSpace
            self.moveSpace = moveSpace
            self.addSpace = addSpace
        }

        // MARK: - Body

        var body: some View {
            HStack(spacing: 8) {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        CrestSpaceIconPicker(
                            spaces: spaces, selectedSpaceID: selectedSpaceID, selectSpace: selectSpace,
                            moveSpace: moveSpace, segmentSize: CGSize(width: 44, height: 44)
                        ) { space in
                            BrowserSpacePickerIcon(space: space, metrics: .touch)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selectedSpaceID) { _, id in
                        reader.scrollTo(id, anchor: .center)
                    }
                }
                Button("New Space", systemImage: "plus", action: addSpace)
                    .labelStyle(.iconOnly)
                    .buttonStyle(CrestChromeButtonStyle())
                    .accessibilityIdentifier("space-customization-add")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .frame(height: 62)
        }
    }
#endif
