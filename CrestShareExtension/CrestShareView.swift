import SwiftUI

/// The share sheet's Crest entry: nothing while the link is handed to
/// Crest, the Space picker when the person chose to pick one, or a short
/// notice when the link could not be opened.
struct CrestShareView: View {
    // MARK: - Static Variables

    private static let iconSize: CGFloat = 28

    // MARK: - Variables

    @Bindable var model: CrestShareModel

    var body: some View {
        switch model.stage {
        case .working:
            Color.clear
        case .choosingSpace(let link, let directory):
            spacePicker(link: link, spaces: directory.spaces)
        case .saved:
            notice(
                "Sent to Crest", systemImage: "checkmark.circle",
                message: "It opens the next time you open Crest.")
        case .noLink:
            notice("No Link to Open", systemImage: "link", message: nil)
        case .couldNotOpen:
            notice("Couldn’t Open Crest", systemImage: "exclamationmark.triangle", message: nil)
        }
    }

    // MARK: - Actions - Choosing a Space

    private func spacePicker(link: BrowserSharedLink, spaces: [BrowserSharedSpaceDirectory.Space]) -> some View {
        NavigationStack {
            List {
                Section {
                    linkSummary(link.url)
                }
                Section("Space") {
                    ForEach(spaces) { space in
                        spaceRow(space)
                    }
                }
            }
            .navigationTitle("Open in Crest")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: model.close)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        Task { await model.openInSelectedSpace() }
                    }
                    .disabled(model.selectedSpaceID == nil)
                }
            }
        }
    }

    private func linkSummary(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
            Text(url.host(percentEncoded: false) ?? url.absoluteString)
                .font(CrestTypography.controlTitle)
            Text(url.absoluteString)
                .font(CrestTypography.metadata)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .accessibilityElement(children: .combine)
    }

    private func spaceRow(_ space: BrowserSharedSpaceDirectory.Space) -> some View {
        Button {
            model.selectedSpaceID = space.id
        } label: {
            HStack(spacing: CrestSpacing.medium) {
                spaceIcon(space)
                Text(space.name)
                    .foregroundStyle(.primary)
                if space.isLocked {
                    Image(systemName: "lock.fill")
                        .font(CrestTypography.metadata)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked")
                }
                Spacer(minLength: CrestSpacing.small)
                if model.selectedSpaceID == space.id {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(model.selectedSpaceID == space.id ? .isSelected : [])
    }

    @ViewBuilder
    private func spaceIcon(_ space: BrowserSharedSpaceDirectory.Space) -> some View {
        if let icon = model.spaceIcons[space.id] {
            Image(uiImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: Self.iconSize, height: Self.iconSize)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "square.stack")
                .frame(width: Self.iconSize, height: Self.iconSize)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Actions - Notices

    private func notice(_ title: LocalizedStringKey, systemImage: String, message: LocalizedStringKey?) -> some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let message {
                    Text(message)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: model.close)
                }
            }
        }
    }
}
