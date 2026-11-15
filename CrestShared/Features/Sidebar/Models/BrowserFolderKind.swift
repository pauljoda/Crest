import SwiftUI

/// What a folder of the sidebar is, a folder or a group, and everything the
/// sidebar draws or does differently for each: its words, which appearance
/// choices draw it, and how it closes and goes.
///
/// The two instances below are the one table of those differences.
@MainActor
struct BrowserFolderKind {
    // MARK: - Static Variables

    /// A folder: its artwork beside its title, folders inside it, its loaded
    /// tabs kept on screen when it closes, and a question before it goes with
    /// everything inside it.
    static let folder = BrowserFolderKind(
        showsArtwork: true, holdsFolders: true, keepsLoadedTabsWhenClosed: true, asksBeforeDeleting: true,
        spokenName: { "\($0) folder" }, collapseHint: "Collapses this folder", expandHint: "Expands this folder",
        actionsTitle: "Folder actions", namePrompt: "Folder Name", colorTitle: "Folder Color",
        removeTitle: "Remove from Folder", renameTitle: "Rename Folder", colorMenuTitle: "Folder Color…",
        convertTitle: "Convert to Group", convertSymbol: "rectangle.stack", saveTitle: "Move to Saved Tabs",
        deleteTitle: "Delete Folder", deleteSymbol: "trash", deleteRole: .destructive,
        showsTabCounts: \.foldersShowTabCounts, showsHighlights: \.foldersAlwaysVisible,
        showsBorders: \.foldersShowBorders, tintsTitle: \.foldersTintTitle)

    /// A group: its name alone, open tabs only, closing to its header and the
    /// tab the window shows, and gone at once when ungrouped, since its tabs
    /// stay where they are.
    static let group = BrowserFolderKind(
        showsArtwork: false, holdsFolders: false, keepsLoadedTabsWhenClosed: false, asksBeforeDeleting: false,
        spokenName: { "\($0) group" }, collapseHint: "Collapses this group", expandHint: "Expands this group",
        actionsTitle: "Group actions", namePrompt: "Group Name", colorTitle: "Group Color",
        removeTitle: "Remove from Group", renameTitle: "Rename Group", colorMenuTitle: "Group Color…",
        convertTitle: "Convert to Folder", convertSymbol: "folder", saveTitle: "Move to Saved Tabs as Folder",
        deleteTitle: "Ungroup", deleteSymbol: "rectangle.stack.badge.minus", deleteRole: nil,
        showsTabCounts: \.groupsShowTabCounts, showsHighlights: \.groupsAlwaysVisible,
        showsBorders: \.groupsShowBorders, tintsTitle: \.groupsTintTitle)

    // MARK: - Variables

    /// Whether the header shows the folder's artwork beside its title, rather
    /// than its name alone in small type, and offers to choose that artwork.
    let showsArtwork: Bool
    /// Whether folders go inside it, and it inside other folders.
    let holdsFolders: Bool
    /// Whether closing it keeps its loaded tabs on screen under its header.
    let keepsLoadedTabsWhenClosed: Bool
    /// Whether deleting it asks first, since it takes what it holds along.
    let asksBeforeDeleting: Bool
    /// What VoiceOver calls the folder titled with the given name.
    let spokenName: (String) -> LocalizedStringKey
    let collapseHint: LocalizedStringKey
    let expandHint: LocalizedStringKey
    /// The name of the `…` button on its header.
    let actionsTitle: LocalizedStringKey
    /// The prompt of the field that renames it.
    let namePrompt: LocalizedStringKey
    /// The title of the popover that chooses its color.
    let colorTitle: LocalizedStringKey
    /// The tab menu item that takes a tab out of it.
    let removeTitle: LocalizedStringKey
    /// Its own menu's items: renaming it, choosing its color, turning it into
    /// the other kind, moving it to the saved tabs, and deleting it.
    let renameTitle: LocalizedStringKey
    let colorMenuTitle: LocalizedStringKey
    let convertTitle: LocalizedStringKey
    let convertSymbol: String
    let saveTitle: LocalizedStringKey
    let deleteTitle: LocalizedStringKey
    let deleteSymbol: String
    let deleteRole: ButtonRole?
    /// The appearance choices that draw it, on this device.
    let showsTabCounts: ReferenceWritableKeyPath<BrowserDeviceAppearanceStore, Bool>
    let showsHighlights: ReferenceWritableKeyPath<BrowserDeviceAppearanceStore, Bool>
    let showsBorders: ReferenceWritableKeyPath<BrowserDeviceAppearanceStore, Bool>
    let tintsTitle: ReferenceWritableKeyPath<BrowserDeviceAppearanceStore, Bool>

    // MARK: - Actions - Presentation

    /// The hint VoiceOver gives for opening or closing it.
    func disclosureHint(isExpanded: Bool) -> LocalizedStringKey {
        isExpanded ? collapseHint : expandHint
    }
}
