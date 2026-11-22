import SwiftUI

/// The Spaces the browser will have once setup finishes, the ones it has and
/// the ones setup brings or makes, each opening its own page: every Space
/// with its Sub-Spaces indented under it and a row to add one, then a new
/// Space. A Space's menu moves it up or down among the Spaces, or takes out
/// one setup made.
struct BrowserSetupSpacesPage: View {
    // MARK: - Types

    /// A Space and the Sub-Spaces that share its session.
    private struct SpaceRows: Identifiable {
        let primary: BrowserSpaceIdentity
        var members: [BrowserSpaceIdentity]

        var id: UUID { primary.id }
    }

    // MARK: - Variables

    /// The browser setup would leave, while there is one to show.
    let preview: BrowserSessionPreview?
    let setup: BrowserManualSetupModel
    /// The Spaces an import brings in, which the list marks as new.
    var incomingSpaceIDs: Set<UUID> = []
    let open: (UUID) -> Void

    // MARK: - Actions - Drawing

    var body: some View {
        Form {
            Section {
                ForEach(groups) { group in
                    row(group.primary, isSubSpace: false)
                    ForEach(group.members) { member in
                        row(member, isSubSpace: true)
                    }
                    if setup.space(group.primary.id) != nil {
                        Button {
                            if let added = setup.addSubSpace(to: group.primary.id) { open(added) }
                        } label: {
                            Label("Add Sub-Space", systemImage: "plus")
                        }
                        .buttonStyle(.crestTertiary)
                        .padding(.leading, BrowserSidebarMetrics.subSpaceIndent)
                        .accessibilityLabel(Text("Add a Sub-Space to \(group.primary.name)"))
                        .accessibilityIdentifier("setup-add-sub-space")
                    }
                }
            } header: {
                BrowserSetupPageHeading("Spaces")
            } footer: {
                Text("A Sub-Space shares its Space’s sign-ins and history, with tabs and a look of its own.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("New Space", systemImage: "plus") {
                    if let added = setup.addSpace() { open(added) }
                }
                .buttonStyle(.crestTertiary)
                .accessibilityIdentifier("setup-add-space")
            }
            if let message = setup.errorMessage {
                Section {
                    Text(message).foregroundStyle(CrestColor.danger)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    /// A Space's row, opening its page; a Sub-Space's sits indented under its
    /// Space, joined to it by a turn.
    private func row(_ space: BrowserSpaceIdentity, isSubSpace: Bool) -> some View {
        Button {
            open(space.id)
        } label: {
            HStack(spacing: CrestSpacing.medium) {
                if isSubSpace {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                BrowserSpaceIdentityIcon(
                    identity: space,
                    size: isSubSpace ? BrowserSetupSpacesPageMetrics.subSpaceIcon : BrowserSetupSpacesPageMetrics.icon)
                Text(space.name)
                    .font(.body.weight(isSubSpace ? .medium : .semibold))
                if incomingSpaceIDs.contains(space.id) {
                    Text("New")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: CrestSpacing.small)
                CrestFormDisclosureChevron()
            }
            .padding(.leading, isSubSpace ? BrowserSidebarMetrics.subSpaceIndent - CrestSpacing.large : 0)
            .contentShape(.rect)
        }
        .buttonStyle(.crestFormRow)
        .accessibilityLabel(isSubSpace ? Text("\(space.name), Sub-Space") : Text(space.name))
        .contextMenu { arrangeMenu(for: space.id, isSubSpace: isSubSpace) }
    }

    /// Moving a Space of the setup up or down among the Spaces, and taking
    /// out one setup made.
    @ViewBuilder
    private func arrangeMenu(for spaceID: UUID, isSubSpace: Bool) -> some View {
        let order = groups.map(\.id)
        Group {
            if !isSubSpace, let index = order.firstIndex(of: spaceID), setup.space(spaceID) != nil {
                if index > 0, setup.space(order[index - 1]) != nil {
                    Button("Move Up", systemImage: "arrow.up") { setup.moveSpace(spaceID, to: order[index - 1]) }
                }
                if index < order.count - 1, setup.space(order[index + 1]) != nil {
                    Button("Move Down", systemImage: "arrow.down") { setup.moveSpace(spaceID, to: order[index + 1]) }
                }
            }
            if setup.space(spaceID)?.isNew == true {
                Button("Remove Space", systemImage: "trash", role: .destructive) { setup.removeSpace(spaceID) }
            }
        }
        .crestMenuActionLabelStyle()
    }

    // MARK: - Actions - Reading

    /// The Spaces of the browser setup would leave, then any new Space the
    /// manual setup makes that the preview does not hold yet, each Space with
    /// the Sub-Spaces that share its session. A Space the browser has that
    /// the preview leaves out goes when setup finishes, as a first launch's
    /// starter Space does when another browser's Spaces come in, so it is not
    /// listed.
    private var groups: [SpaceRows] {
        let previewSpaces = preview?.spaces ?? []
        let shownIDs = Set(previewSpaces.map(\.id))
        var listed = previewSpaces.map { space in
            (
                identity: BrowserSpaceIdentity(space: space),
                primaryID: setup.space(space.id)?.primaryID ?? space.membership?.primaryID
            )
        }
        listed += setup.spaces.filter { $0.isNew && !shownIDs.contains($0.spaceID) }.map { draft in
            (identity: BrowserSpaceIdentity(draft: draft), primaryID: draft.primaryID)
        }
        let listedIDs = Set(listed.map(\.identity.id))
        var groups: [SpaceRows] = []
        for space in listed where space.primaryID.map({ !listedIDs.contains($0) }) ?? true {
            groups.append(SpaceRows(primary: space.identity, members: []))
        }
        for space in listed {
            guard let primaryID = space.primaryID, let index = groups.firstIndex(where: { $0.id == primaryID }) else {
                continue
            }
            groups[index].members.append(space.identity)
        }
        return groups
    }
}

enum BrowserSetupSpacesPageMetrics {
    static let icon: CGFloat = 26
    static let subSpaceIcon: CGFloat = 22
}
