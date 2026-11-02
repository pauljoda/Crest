import SwiftUI
import UniformTypeIdentifiers

/// The Settings pane list: a search field over the platform's own sidebar list,
/// grouped the way the macOS catalog orders it, with the Spaces between the
/// last two groups.
struct BrowserSettingsSidebar: View {
    @Environment(\.locale) private var locale
    @State private var standaloneScroll = BrowserNativeScrollState()
    @State private var pendingDeletion: BrowserSpaceDeletionRequest?
    @State private var pendingGroupChange: BrowserSpaceGroupChange?
    @State private var hoveredItem: BrowserSettingsSidebarItem?
    @State private var dropTargetID: UUID?
    @Bindable var tabState: BrowserSettingsTabState
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let openSpace: BrowserSettingsOpenSpaceAction
    let addSpace: () -> Void
    let addSubSpace: (UUID) -> Void
    @FocusState private var isSearchFocused: Bool

    private var navigation: BrowserSettingsNavigationState { tabState.navigation }
    private var state: CoreState { browser.core.state }

    var body: some View {
        VStack(spacing: 0) {
            BrowserSettingsBuildHeader()
            searchField
            List(selection: selection) {
                if let first = visibleGroups.first {
                    destinationSection(first)
                }
                spacesSection
                ForEach(Array(visibleGroups.dropFirst().enumerated()), id: \.offset) { _, group in
                    destinationSection(group)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .browserNativeScrollState(tabState.sidebarScroll)
        }
        .background(BrowserSettingsCanvas.background)
        .browserSpaceDeletionConfirmation(
            $pendingDeletion, browser: browser, spaceAccess: spaceAccess, dataDeleter: dataDeleter
        )
        .browserSpaceGroupChangeConfirmation($pendingGroupChange, browser: browser, spaceAccess: spaceAccess)
        .onChange(of: navigation.query.isEmpty) { _, isEmpty in
            if !isEmpty { tabState.isArrangingSpaces = false }
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search settings", text: $tabState.navigation.searchText)
                .textFieldStyle(.plain).focused($isSearchFocused)
            if !navigation.searchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { tabState.navigation.searchText = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 7))
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Destinations

    private func destinationSection(_ group: [BrowserSettingsDestination]) -> some View {
        Section {
            ForEach(group) { destination in
                Label {
                    Text(destination.navigationTitle)
                } icon: {
                    Image(systemName: destination.symbol)
                        .foregroundStyle(destination.sidebarTint)
                }
                .settingsSidebarRow(.destination(destination), hovered: $hoveredItem, selection: selection)
                .accessibilityIdentifier("settings-\(destination.name)")
            }
        }
    }

    /// The catalog's groups, keeping only the destinations the search shows.
    private var visibleGroups: [[BrowserSettingsDestination]] {
        let visible = Set(navigation.visibleDestinations(locale: locale, in: state))
        return BrowserPlatformSettingsDestinationCatalog.groups
            .map { group in group.filter(visible.contains) }
    }

    // MARK: - Spaces

    @ViewBuilder
    private var spacesSection: some View {
        let spaces = visibleSpaces
        if !spaces.isEmpty || navigation.query.isEmpty {
            Section {
                if tabState.isArrangingSpaces {
                    ForEach(spaces) { space in spaceRow(space) }
                        .onMove { source, destination in
                            guard source.count == 1, let from = source.first else { return }
                            place(spaces[from], before: destination, in: spaces)
                        }
                } else {
                    ForEach(spaces) { space in spaceRow(space) }
                        .onInsert(of: [.plainText]) { index, _ in
                            defer { tabState.draggedSpaceID = nil }
                            guard let space = tabState.draggedSpaceID.flatMap({ browser.spaceModel($0) }) else {
                                return
                            }
                            place(space, before: index, in: spaces)
                        }
                }
            } header: {
                spacesHeader
            }
        }
    }

    private var spacesHeader: some View {
        HStack(spacing: BrowserSettingsSidebarMetrics.headerButtonSpacing) {
            Text("Spaces")
            Spacer(minLength: 4)
            if navigation.query.isEmpty {
                let arranging = tabState.isArrangingSpaces
                Button {
                    tabState.isArrangingSpaces.toggle()
                } label: {
                    Image(systemName: arranging ? "checkmark" : "pencil")
                        .foregroundStyle(arranging ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                }
                .help(arranging ? "Done" : "Rearrange Spaces")
                .accessibilityLabel(arranging ? "Done" : "Rearrange Spaces")
                .accessibilityIdentifier("settings-spaces-arrange")
                .disabled(browser.spaceModels.count < 2 && !arranging)

                Button(action: addSpace) {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                }
                .help("Add Space")
                .accessibilityLabel("Add Space")
                .accessibilityIdentifier("settings-spaces-add")
            }
        }
        .buttonStyle(CrestChromeButtonStyle(controlSize: BrowserSettingsSidebarMetrics.headerButtonSize))
        .font(.system(size: 12, weight: .medium))
        .padding(.trailing, BrowserSettingsSidebarMetrics.headerTrailingInset)
        .accessibilityElement(children: .contain)
    }

    /// A Space's row: its crest and name, a Sub-Space indented under its
    /// primary. Choosing it shows the Space's page, as choosing its crest in
    /// the page's crest row does, so the two always select the same Space.
    private func spaceRow(_ space: SpaceModel) -> some View {
        HStack(spacing: 6) {
            // A Sub-Space sits under its primary, as a tab sits in a folder.
            if browser.isSubSpace(space) {
                Color.clear.frame(width: BrowserSettingsSidebarMetrics.subSpaceIndent, height: 1)
                    .accessibilityHidden(true)
            }
            Label {
                Text(space.settings.name.isEmpty ? String(localized: "Untitled Space") : space.settings.name)
                    .lineLimit(1)
            } icon: {
                BrowserSpaceIdentityIcon(space: space, size: 18)
            }
            Spacer(minLength: 4)
            if tabState.isArrangingSpaces {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Drag to reorder")
            } else {
                if space.settings.requiresAuthentication {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked")
                }
                if selection.wrappedValue == .space(space.id) {
                    Menu {
                        spaceMenu(space)
                            .crestMenuActionLabelStyle()
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Space actions")
                    .accessibilityLabel("Space actions")
                }
            }
        }
        .settingsSidebarRow(
            .space(space.id), hovered: $hoveredItem, selection: selection,
            isDropTarget: dropTargetID == browser.primary(of: space).id
        )
        .moveDisabled(!tabState.isArrangingSpaces)
        .contextMenu { spaceMenu(space).crestMenuActionLabelStyle() }
        .modifier(
            BrowserSettingsSpaceGroupDrag(
                space: space, browser: browser, isArranging: tabState.isArrangingSpaces,
                draggedSpaceID: $tabState.draggedSpaceID, dropTargetID: $dropTargetID
            ) { dragged in requestJoin(of: dragged, into: browser.primary(of: space)) }
        )
        .accessibilityIdentifier("settings-space-\(space.id)")
    }

    /// Asks to make `space` a Sub-Space of `group`'s group. Answers whether it
    /// may join it.
    private func requestJoin(of space: SpaceModel, into group: SpaceModel) -> Bool {
        guard space !== group, let change = BrowserSpaceGroupChange.joining(space, into: group, in: browser) else {
            return false
        }
        pendingGroupChange = change
        return true
    }

    /// Places `space` where a drag left it, before the row at `index` of
    /// `spaces`, as a tab moves among folders: among another group's
    /// Sub-Spaces it asks to join that group, among its own it moves there,
    /// and between groups a Sub-Space asks to come out on its own while a
    /// group moves whole.
    private func place(_ space: SpaceModel, before index: Int, in spaces: [SpaceModel]) {
        let next = spaces.indices.contains(index) ? spaces[index] : nil
        if let next, browser.isSubSpace(next) {
            let group = browser.primary(of: next)
            if browser.isSubSpace(space), browser.primary(of: space) === group {
                browser.move(space.id, before: next.id)
            } else {
                _ = requestJoin(of: space, into: group)
            }
        } else if let change = BrowserSpaceGroupChange.separating(space, in: browser) {
            pendingGroupChange = change
        } else {
            browser.moveGroup(of: space.id, before: next?.id)
        }
    }

    private func spaceMenu(_ space: SpaceModel) -> some View {
        BrowserSettingsSpaceMenu(
            browser: browser, space: space, spaceAccess: spaceAccess, openSpace: openSpace, addSubSpace: addSubSpace,
            requestDeletion: { pendingDeletion = $0 }, requestGroupChange: { pendingGroupChange = $0 })
    }

    /// Every Space while arranging, each group's primary then its
    /// Sub-Spaces; otherwise the groups with a Space the search shows, whole.
    private var visibleSpaces: [SpaceModel] {
        let groups = browser.spaceGroups
        guard !tabState.isArrangingSpaces else { return groups.flatMap { $0 } }
        let tab = navigation.matchingSpaceTab(locale: locale, in: state)
        return groups.filter { group in group.contains { navigation.lists($0, spaceTab: tab) } }.flatMap { $0 }
    }

    // MARK: - Selection

    /// The list's selection. A page without a row selects the row it lives
    /// under; clearing the selection is ignored, so a pane is always shown.
    private var selection: Binding<BrowserSettingsSidebarItem?> {
        Binding {
            navigation.selection.row
        } set: { item in
            item?.select(on: tabState) { id in
                openSpace(id, tab: navigation.matchingSpaceTab(locale: locale, in: state))
            }
        }
    }
}

extension View {
    /// A sidebar row for `item`, wearing Crest's hover surface while the
    /// pointer is over it unless it is the selected row, and while a dragged
    /// Space would join its group.
    fileprivate func settingsSidebarRow(
        _ item: BrowserSettingsSidebarItem,
        hovered: Binding<BrowserSettingsSidebarItem?>,
        selection: Binding<BrowserSettingsSidebarItem?>,
        isDropTarget: Bool = false
    ) -> some View {
        // A row a dragged Space would join wears the hover surface too.
        let isHovered = (hovered.wrappedValue == item && selection.wrappedValue != item) || isDropTarget
        return
            self
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .onHover { inside in
                if inside {
                    hovered.wrappedValue = item
                } else if hovered.wrappedValue == item {
                    hovered.wrappedValue = nil
                }
            }
            .listRowBackground(
                Color.clear
                    .crestInteractiveSurface(isSelected: false, isHovering: isHovered)
                    .padding(.horizontal, BrowserSettingsSidebarMetrics.rowHighlightInset)
            )
            .tag(item)
    }
}

private enum BrowserSettingsSidebarMetrics {
    /// Matches the inset of the sidebar's own selection highlight.
    static let rowHighlightInset: CGFloat = 10
    static let headerButtonSpacing: CGFloat = 4
    /// Lines the header's buttons up with the trailing glyphs of the rows.
    static let headerTrailingInset: CGFloat = 6
    static let headerButtonSize = CGSize(width: 22, height: 22)
    /// How far a Sub-Space's row sits in from its primary's.
    static let subSpaceIndent: CGFloat = 14
}

/// Lets a Space's Settings row take a Space dragged onto it, from another row
/// or from a group page's crests, which asks to make it a Sub-Space of the
/// row's group. A Space on its own and a Sub-Space drag from their rows the
/// same way; a primary stays, since its group goes where it goes. While the
/// person arranges Spaces, rows reorder instead.
private struct BrowserSettingsSpaceGroupDrag: ViewModifier {
    let space: SpaceModel
    let browser: BrowserStore
    let isArranging: Bool
    @Binding var draggedSpaceID: UUID?
    @Binding var dropTargetID: UUID?
    let join: (SpaceModel) -> Bool

    func body(content: Content) -> some View {
        if isArranging {
            content
        } else if !browser.leadsGroup(space) {
            content
                .onDrag {
                    draggedSpaceID = space.id
                    return NSItemProvider(object: space.id.uuidString as NSString)
                }
                .onDrop(of: [.plainText], delegate: dropDelegate)
        } else {
            content.onDrop(of: [.plainText], delegate: dropDelegate)
        }
    }

    private var dropDelegate: RowDrop {
        RowDrop(
            primary: browser.primary(of: space), browser: browser, draggedSpaceID: $draggedSpaceID,
            dropTargetID: $dropTargetID, join: join)
    }

    /// A row taking a dragged Space, which asks to join the row's group,
    /// whose rows all show it.
    private struct RowDrop: DropDelegate {
        let primary: SpaceModel
        let browser: BrowserStore
        @Binding var draggedSpaceID: UUID?
        @Binding var dropTargetID: UUID?
        let join: (SpaceModel) -> Bool

        private var dragged: SpaceModel? {
            draggedSpaceID.flatMap { browser.spaceModel($0) }
        }

        func validateDrop(info: DropInfo) -> Bool {
            guard let dragged, dragged !== primary else { return false }
            return BrowserSpaceGroupChange.joining(dragged, into: primary, in: browser) != nil
        }

        func dropEntered(info: DropInfo) {
            if validateDrop(info: info) { dropTargetID = primary.id }
        }

        func dropExited(info: DropInfo) {
            if dropTargetID == primary.id { dropTargetID = nil }
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: validateDrop(info: info) ? .move : .forbidden)
        }

        func performDrop(info: DropInfo) -> Bool {
            defer {
                dropTargetID = nil
                draggedSpaceID = nil
            }
            guard let dragged else { return false }
            return join(dragged)
        }
    }
}
