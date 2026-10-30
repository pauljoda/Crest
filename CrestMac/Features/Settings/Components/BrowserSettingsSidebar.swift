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
        let groups = visibleSpaceGroups
        if !groups.isEmpty || navigation.query.isEmpty {
            Section {
                if tabState.isArrangingSpaces {
                    ForEach(groups, id: \.[0].id) { group in groupRow(group) }
                        .onMove { source, destination in browser.moveGroups(from: source, to: destination) }
                } else {
                    // A Sub-Space dropped between groups comes out on its own; a
                    // Space on its own moves there.
                    ForEach(groups, id: \.[0].id) { group in groupRow(group) }
                        .onInsert(of: [.plainText]) { index, _ in placeDraggedSpace(at: index, among: groups) }
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

    /// A group's row: its primary's crest and name, with its Sub-Spaces'
    /// crests stacked behind. Its page edits each of them.
    private func groupRow(_ group: [SpaceModel]) -> some View {
        let primary = group[0]
        let isLocked = group.contains { $0.settings.requiresAuthentication }
        return HStack(spacing: 6) {
            Label {
                Text(primary.settings.name.isEmpty ? String(localized: "Untitled Space") : primary.settings.name)
                    .lineLimit(1)
            } icon: {
                BrowserSpaceGroupIcon(members: group, size: 18)
            }
            Spacer(minLength: 4)
            if tabState.isArrangingSpaces {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Drag to reorder")
            } else {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Locked")
                }
                if selection.wrappedValue == .space(primary.id) {
                    Menu {
                        spaceMenu(primary)
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
            .space(primary.id), hovered: $hoveredItem, selection: selection, isDropTarget: dropTargetID == primary.id
        )
        .moveDisabled(!tabState.isArrangingSpaces)
        .contextMenu { spaceMenu(primary) }
        .modifier(
            BrowserSettingsSpaceGroupDrag(
                group: group, browser: browser, isArranging: tabState.isArrangingSpaces,
                draggedSpaceID: $tabState.draggedSpaceID, dropTargetID: $dropTargetID
            ) { space in requestJoin(of: space, into: primary) }
        )
        .accessibilityIdentifier("settings-space-\(primary.id)")
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

    /// Places the Space being dragged between the groups `groups` lists, at
    /// `index`: a Sub-Space asks to come out of its group, and a Space on its
    /// own moves there.
    private func placeDraggedSpace(at index: Int, among groups: [[SpaceModel]]) {
        defer { tabState.draggedSpaceID = nil }
        guard let space = tabState.draggedSpaceID.flatMap({ browser.spaceModel($0) }) else { return }
        if let change = BrowserSpaceGroupChange.separating(space, in: browser) {
            pendingGroupChange = change
        } else if let from = groups.firstIndex(where: { $0.count == 1 && $0[0].id == space.id }) {
            browser.moveGroups(from: IndexSet(integer: from), to: index)
        }
    }

    private func spaceMenu(_ space: SpaceModel) -> some View {
        BrowserSettingsSpaceMenu(
            browser: browser, space: space, spaceAccess: spaceAccess, openSpace: openSpace, addSubSpace: addSubSpace,
            requestDeletion: { pendingDeletion = $0 }, requestGroupChange: { pendingGroupChange = $0 })
    }

    /// Every group of Spaces while arranging; otherwise the groups with a
    /// Space the search shows.
    private var visibleSpaceGroups: [[SpaceModel]] {
        let groups = browser.spaceGroups
        guard !tabState.isArrangingSpaces else { return groups }
        let tab = navigation.matchingSpaceTab(locale: locale, in: state)
        return groups.filter { group in group.contains { navigation.lists($0, spaceTab: tab) } }
    }

    // MARK: - Selection

    /// The primary of the group whose page is shown, if a Space's is.
    private var currentGroupPrimaryID: UUID? {
        guard case .space(let id) = navigation.selection.row, let space = browser.spaceModel(id) else { return nil }
        return browser.primary(of: space).id
    }

    /// The list's selection. A page without a row selects the row it lives
    /// under; clearing the selection is ignored, so a pane is always shown.
    private var selection: Binding<BrowserSettingsSidebarItem?> {
        Binding {
            guard case .space(let id) = navigation.selection.row, let space = browser.spaceModel(id) else {
                return navigation.selection.row
            }
            return .space(browser.primary(of: space).id)
        } set: { item in
            // Choosing the row of the group shown keeps the Space shown.
            if item == .space(currentGroupPrimaryID ?? UUID()) { return }
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

/// Lets a group's Settings row take a Space dragged onto it, from another
/// row or from a group page's crests, which asks to make it a Sub-Space there.
/// A Space on its own drags from its row the same way. While the person
/// arranges Spaces, rows reorder instead.
private struct BrowserSettingsSpaceGroupDrag: ViewModifier {
    let group: [SpaceModel]
    let browser: BrowserStore
    let isArranging: Bool
    @Binding var draggedSpaceID: UUID?
    @Binding var dropTargetID: UUID?
    let join: (SpaceModel) -> Bool

    func body(content: Content) -> some View {
        if isArranging {
            content
        } else if group.count == 1 {
            content
                .onDrag {
                    draggedSpaceID = group[0].id
                    return NSItemProvider(object: group[0].id.uuidString as NSString)
                }
                .onDrop(of: [.plainText], delegate: dropDelegate)
        } else {
            content.onDrop(of: [.plainText], delegate: dropDelegate)
        }
    }

    private var dropDelegate: RowDrop {
        RowDrop(
            primary: group[0], browser: browser, draggedSpaceID: $draggedSpaceID, dropTargetID: $dropTargetID,
            join: join)
    }

    /// A group's row taking a dragged Space, which asks to join the group.
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
