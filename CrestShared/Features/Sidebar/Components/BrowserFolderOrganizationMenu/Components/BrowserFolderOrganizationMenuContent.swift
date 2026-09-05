import SwiftUI

struct BrowserFolderOrganizationMenuContent: View {
    let folder: BrowserFolder
    let assignment: BrowserFolderRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let createNestedFolder: () -> Void
    let renameFolder: () -> Void
    let changeColor: () -> Void
    let deleteFolder: () -> Void

    init(menu: BrowserFolderOrganizationMenu) {
        folder = menu.folder
        assignment = menu.assignment
        browser = menu.browser
        spaceAccess = menu.spaceAccess
        createNestedFolder = menu.createNestedFolder
        renameFolder = menu.renameFolder
        changeColor = menu.changeColor
        deleteFolder = menu.deleteFolder
    }

    var body: some View {
        Button("New Nested Folder", systemImage: "folder.badge.plus") {
            performIfCurrent(createNestedFolder)
        }
        .disabled(!canCreateNestedFolder)
        Button("Rename Folder", systemImage: "pencil") {
            performIfCurrent(renameFolder)
        }
        Button("Folder Color…", systemImage: "paintpalette") {
            performIfCurrent(changeColor)
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

                if !moveDestinations.isEmpty {
                    Divider()
                    ForEach(moveDestinations) { destination in
                        Button(
                            destination.path,
                            systemImage: destination.node.folder.symbol
                        ) {
                            performIfCurrent {
                                browser.moveFolder(
                                    folder.id,
                                    matching: assignment.spaceAssignment,
                                    into: destination.node.id
                                )
                            }
                        }
                        .disabled(folder.parentID == destination.node.id)
                    }
                }
            }
            .crestMenuActionLabelStyle()
        }

        Divider()
        Button("Delete Folder", systemImage: "trash", role: .destructive) {
            performIfCurrent(deleteFolder)
        }
    }

    private var canCreateNestedFolder: Bool {
        guard let space = currentUnlockedSpace,
            space.folders.count < BrowserSpace.maximumFolderCount,
            let depth = space.folderTree.depth(of: folder.id)
        else { return false }
        return depth + 1 < BrowserSpace.maximumFolderDepth
    }

    private var moveDestinations: [BrowserFolderMoveDestination] {
        guard let space = currentUnlockedSpace else { return [] }
        let tree = space.folderTree
        let excluded = tree.descendants(of: folder.id).union([folder.id])
        return tree.flattenedNodes(collapsedFolderIDs: []).compactMap { node in
            guard !excluded.contains(node.id),
                browser.canMoveFolder(
                    folder.id,
                    matching: assignment.spaceAssignment,
                    into: node.id
                )
            else {
                return nil
            }
            return BrowserFolderMoveDestination(
                node: node,
                path: (node.folder.location == .saved
                    ? String(localized: "Saved Tabs") : String(localized: "Current Tabs"))
                    + " › " + (tree.pathTitle(for: node.id) ?? node.folder.title)
            )
        }
    }

    private var currentUnlockedSpace: BrowserSpace? {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: assignment.spaceAssignment,
                in: browser,
                accessController: spaceAccess
            ),
            space.folders.contains(where: { $0.id == folder.id })
        else { return nil }
        return space
    }

    private func performIfCurrent(_ action: () -> Void) {
        guard currentUnlockedSpace != nil else { return }
        action()
    }
}
