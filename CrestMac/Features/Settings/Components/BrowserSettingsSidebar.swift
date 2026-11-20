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
                    BrowserSettingsSidebarGlyph(destination: destination)
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

    /// The Space's name and crest, with its primary's name below a Sub-Space.
    private func spaceRow(_ space: SpaceModel) -> some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading) {
                    Text(space.settings.name.isEmpty ? String(localized: "Untitled Space") : space.settings.name)
                    if browser.isSubSpace(space) {
                        Text("Sub-Space of \(browser.primary(of: space).settings.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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

    /// Dropping between rows sets the Space's position. A drop onto a row asks to join its group.
    private func place(_ space: SpaceModel, before index: Int, in spaces: [SpaceModel]) {
        browser.move(space.id, before: spaces.indices.contains(index) ? spaces[index].id : nil)
    }

    private func spaceMenu(_ space: SpaceModel) -> some View {
        BrowserSettingsSpaceMenu(
            browser: browser, space: space, spaceAccess: spaceAccess, openSpace: openSpace, addSubSpace: addSubSpace,
            requestDeletion: { pendingDeletion = $0 }, requestGroupChange: { pendingGroupChange = $0 })
    }

    /// The workspace order, including every member of a group that matches the search.
    private var visibleSpaces: [SpaceModel] {
        let spaces = browser.availableSpaces
        guard !navigation.query.isEmpty else { return spaces }
        let tab = navigation.matchingSpaceTab(locale: locale, in: state)
        let matched = spaces.filter { navigation.lists($0, spaceTab: tab) }
        let primaries = Set(matched.map { browser.primary(of: $0).id })
        return spaces.filter { primaries.contains(browser.primary(of: $0).id) }
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
}

/// Lets a Space's Settings row take a Space dragged onto it, from another row
/// or from a group page's crests, which asks to make it a Sub-Space of the
/// row's group. A Space on its own and a Sub-Space drag from their rows the
/// same way. While arranging, every row can move to a new position.
private struct BrowserSettingsSpaceGroupDrag: ViewModifier {
    let space: SpaceModel
    let browser: BrowserStore
    let isArranging: Bool
    @Binding var draggedSpaceID: UUID?
    @Binding var dropTargetID: UUID?
    let join: (SpaceModel) -> Bool

    /// The row as it takes drags: none while arranging, a drop for a group's
    /// primary, and a drag and a drop for any other Space.
    func body(content: Content) -> some View {
        if isArranging {
            content
        } else if !browser.leadsGroup(space) {
            // The list drags the row as it drags any row, once the pointer
            // has moved a few points, so a click that moves a little still
            // chooses the Space. A drag of the row's own starts after a
            // point and keeps such a click from choosing it.
            content
                .itemProvider {
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
