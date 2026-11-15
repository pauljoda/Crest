import SwiftUI

/// A folder's actions, and a group's, as the folder's kind words and offers
/// them: a group holds no folders and sits in none, so it offers neither, and
/// moving it to the saved tabs makes it a folder there, which its menu item
/// says.
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
        let kind = folder.kind
        if kind.holdsFolders {
            Button("New Nested Folder", systemImage: "folder.badge.plus") {
                performIfCurrent(createNestedFolder)
            }
            .disabled(!canCreateNestedFolder)
        }
        Button(kind.renameTitle, systemImage: "pencil") {
            performIfCurrent(renameFolder)
        }
        if kind.showsArtwork {
            Button("Folder Icon…", systemImage: "face.smiling") {
                performIfCurrent(changeIcon)
            }
        }
        Button(kind.colorMenuTitle, systemImage: "paintpalette") {
            performIfCurrent(changeColor)
        }
        if folder.location == .current {
            Button(kind.convertTitle, systemImage: kind.convertSymbol) {
                performIfCurrent {
                    browser.setSessionFolderGroup(folder.id, in: assignment.spaceID, isGroup: !folder.isGroup)
                }
            }
            .disabled(
                !isCurrentAndUnlocked
                    || !browser.canSetSessionFolderGroup(folder.id, in: assignment.spaceID, isGroup: !folder.isGroup))
        }

        Button(
            folder.location == .current ? kind.saveTitle : "Move to Current Tabs",
            systemImage: folder.location == .current ? "bookmark" : "rectangle.stack"
        ) {
            performIfCurrent {
                browser.moveFolder(
                    folder.id, matching: assignment.spaceAssignment,
                    to: folder.location == .current ? .saved : .current)
            }
        }

        if kind.holdsFolders {
            folderMoves
        }
        spaceActions
        if folder.location == .current {
            Divider()
            Button("Archive Tabs", systemImage: "archivebox") {
                performIfCurrent(archiveTabs)
            }
            .disabled(archiving.map { !batchActions.isAvailable($0.batch) } ?? true)
        }

        Divider()
        Button(kind.deleteTitle, systemImage: kind.deleteSymbol, role: kind.deleteRole) {
            performIfCurrent(deleteFolder)
        }
    }

    /// Moving the folder into another folder, or to the top level.
    private var folderMoves: some View {
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

    /// Moving the folder or group, with everything it holds, to another Space.
    @ViewBuilder
    private var spaceActions: some View {
        let otherSpaces = destinationSpaces
        if !otherSpaces.isEmpty {
            Menu("Move to Space", systemImage: "square.grid.2x2") {
                ForEach(Array(browser.grouped(otherSpaces).enumerated()), id: \.offset) { index, group in
                    if index > 0 { Divider() }
                    ForEach(group) { space in
                        moveButton(to: space)
                    }
                }
                .crestMenuActionLabelStyle()
            }
            .tint(.primary)
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

    /// The other Spaces the folder may move to, as a tab's menu offers them.
    private var destinationSpaces: [SpaceModel] {
        guard isCurrentAndUnlocked else { return [] }
        return browser.availableTabMoveDestinationSpaces(
            from: assignment.spaceAssignment, accessController: context.spaceAccess)
    }

    /// Moves the folder, with everything inside it, to `space`, once that
    /// Space is unlocked.
    private func moveButton(to space: SpaceModel) -> some View {
        let destination = BrowserSpaceRuntimeAssignment(space: space)
        return Button {
            performIfCurrent {
                guard browser.unlockedSpace(matching: destination, accessController: context.spaceAccess) != nil
                else { return }
                browser.moveFolder(folder.id, matching: assignment.spaceAssignment, toSpace: destination)
            }
        } label: {
            BrowserSpaceIdentityLabel(space: space)
        }
        .disabled(!browser.canMoveFolder(folder.id, matching: assignment.spaceAssignment, toSpace: destination))
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
