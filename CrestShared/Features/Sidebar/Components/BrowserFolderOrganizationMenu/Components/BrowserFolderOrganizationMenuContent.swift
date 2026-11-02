import SwiftUI

/// A folder's actions, and a group's: a group holds no folders and sits in
/// none, so it offers neither, and moving it to the saved tabs makes it a
/// folder there, which its menu item says.
struct BrowserFolderOrganizationMenuContent: View {
    let folder: FolderStateModel
    let context: BrowserSidebarListContext
    let assignment: BrowserFolderRuntimeAssignment
    let createNestedFolder: () -> Void
    let renameFolder: () -> Void
    let changeColor: () -> Void
    let changeIcon: () -> Void
    let deleteFolder: () -> Void

    init(menu: BrowserFolderOrganizationMenu) {
        folder = menu.folder
        context = menu.context
        assignment = menu.assignment
        createNestedFolder = menu.createNestedFolder
        renameFolder = menu.renameFolder
        changeColor = menu.changeColor
        changeIcon = menu.changeIcon
        deleteFolder = menu.deleteFolder
    }

    private var browser: BrowserStore { context.browser }

    var body: some View {
        if folder.isGroup {
            groupActions
        } else {
            folderActions
        }
        if folder.location == .current {
            Divider()
            Button("Archive Tabs", systemImage: "archivebox") {
                performIfCurrent(archiveTabs)
            }
            .disabled(archiving.map { !batchActions.isAvailable($0.batch) } ?? true)
        }

        Divider()
        if folder.isGroup {
            Button("Ungroup", systemImage: "rectangle.stack.badge.minus") {
                performIfCurrent(deleteFolder)
            }
        } else {
            Button("Delete Folder", systemImage: "trash", role: .destructive) {
                performIfCurrent(deleteFolder)
            }
        }
    }

    @ViewBuilder
    private var groupActions: some View {
        Button("Rename Group", systemImage: "pencil") {
            performIfCurrent(renameFolder)
        }
        Button("Group Color…", systemImage: "paintpalette") {
            performIfCurrent(changeColor)
        }
        Button("Convert to Folder", systemImage: "folder") {
            performIfCurrent { browser.setSessionFolderGroup(folder.id, in: assignment.spaceID, isGroup: false) }
        }
        Button("Move to Saved Tabs as Folder", systemImage: "bookmark") {
            performIfCurrent {
                browser.moveFolder(folder.id, matching: assignment.spaceAssignment, to: .saved)
            }
        }
    }

    @ViewBuilder
    private var folderActions: some View {
        Button("New Nested Folder", systemImage: "folder.badge.plus") {
            performIfCurrent(createNestedFolder)
        }
        .disabled(!canCreateNestedFolder)
        Button("Rename Folder", systemImage: "pencil") {
            performIfCurrent(renameFolder)
        }
        Button("Folder Icon…", systemImage: "face.smiling") {
            performIfCurrent(changeIcon)
        }
        Button("Folder Color…", systemImage: "paintpalette") {
            performIfCurrent(changeColor)
        }
        if folder.location == .current {
            Button("Convert to Group", systemImage: "rectangle.stack") {
                performIfCurrent { browser.setSessionFolderGroup(folder.id, in: assignment.spaceID, isGroup: true) }
            }
            .disabled(
                !isCurrentAndUnlocked
                    || !browser.canSetSessionFolderGroup(folder.id, in: assignment.spaceID, isGroup: true))
        }

        Button(
            folder.location == .current ? "Move to Saved Tabs" : "Move to Current Tabs",
            systemImage: folder.location == .current ? "bookmark" : "rectangle.stack"
        ) {
            performIfCurrent {
                browser.moveFolder(
                    folder.id, matching: assignment.spaceAssignment,
                    to: folder.location == .current ? .saved : .current)
            }
        }

        Menu("Move to Folder", systemImage: "folder.badge.gearshape") {
            Group {
                Button(
                    "Top Level",
                    systemImage: "rectangle.topthird.inset.filled"
                ) {
                    performIfCurrent {
                        browser.moveFolder(
                            folder.id,
                            matching: assignment.spaceAssignment,
                            into: nil
                        )
                    }
                }
                .disabled(folder.parentID == nil)

                let destinations = moveDestinations
                if !destinations.isEmpty {
                    Divider()
                    ForEach(destinations) { destination in
                        Button {
                            performIfCurrent {
                                browser.moveFolder(
                                    folder.id,
                                    matching: assignment.spaceAssignment,
                                    into: destination.folder.id
                                )
                            }
                        } label: {
                            Label {
                                Text(destination.path)
                            } icon: {
                                BrowserFolderArtwork(
                                    symbol: destination.folder.displaySymbol, color: destination.folder.displayColor)
                            }
                        }
                        .disabled(folder.parentID == destination.folder.id)
                    }
                }
            }
            .crestMenuActionLabelStyle()
        }
    }

    private var batchActions: BrowserTabBatchActions {
        BrowserTabBatchActions(browser: browser, spaceAccess: context.spaceAccess)
    }

    /// Archiving every tab the folder holds, as a selection of those tabs.
    private var archiving: (request: BrowserCapturedSelection, batch: BrowserTabBatch)? {
        guard isCurrentAndUnlocked else { return nil }
        let tabs = context.space.tabIDs(inFolder: folder.id)
        guard !tabs.isEmpty,
            let request = BrowserSidebarSelection.capture(tabs.map { .tab($0) }, in: browser)
        else { return nil }
        return (request, browser.closing(request))
    }

    private func archiveTabs() {
        guard let archiving else { return }
        _ = batchActions.perform(archiving.batch, for: archiving.request)
    }

    private var isCurrentAndUnlocked: Bool {
        context.isCurrent(assignment.spaceAssignment) && context.space.folders.contains(folder.id)
    }

    private var canCreateNestedFolder: Bool {
        guard isCurrentAndUnlocked else { return false }
        return browser.canAddFolder(inside: folder.id, matching: assignment.spaceAssignment)
    }

    /// Every other folder the core would take this one into, saved folders
    /// first, each named by its section and the folders around it.
    private var moveDestinations: [BrowserFolderMoveDestination] {
        guard isCurrentAndUnlocked else { return [] }
        let space = context.space
        let excluded = Set(space.folderChoices(inside: folder.id).map(\.id)).union([folder.id])
        return space.folderChoices(in: [.saved, .current]).compactMap { choice in
            guard !excluded.contains(choice.id),
                browser.canMoveFolder(folder.id, matching: assignment.spaceAssignment, into: choice.id)
            else { return nil }
            let section =
                choice.folder.location == .saved
                ? String(localized: "Saved Tabs") : String(localized: "Current Tabs")
            return BrowserFolderMoveDestination(folder: choice.folder, path: section + " › " + choice.pathTitle)
        }
    }

    private func performIfCurrent(_ action: () -> Void) {
        guard isCurrentAndUnlocked else { return }
        action()
    }
}
