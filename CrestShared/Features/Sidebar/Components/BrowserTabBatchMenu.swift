import SwiftUI

struct BrowserTabBatchMenu: View {
    let request: BrowserTabBatchRequest
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var unload: ((TabID) -> Void)? = nil

    private var actions: BrowserTabBatchActions { BrowserTabBatchActions(browser: browser, spaceAccess: spaceAccess) }
    private var count: Int { request.ids.count }

    var body: some View {
        if request.hasFolders { folderMenu } else { tabMenu }
    }

    @ViewBuilder
    private var tabMenu: some View {
        Group {
            if count == 1 { Text("1 tab selected") } else { Text("\(count) tabs selected") }
        }
        .disabled(true)
        Divider()
        Button("Copy Link URLs", systemImage: "link", action: copyLinks)
        Divider()
        Button("Pin \(count) Tabs", systemImage: "pin") { perform(.file(.pinned)) }
        Button("Move to Current Tabs", systemImage: "rectangle.stack") { perform(.file(.current)) }
        Menu("Move to Folder", systemImage: "folder") {
            Button("New Current Tabs Folder") { perform(.newFolder(.current)) }
            Button("New Saved Folder") { perform(.newFolder(.saved)) }
            Button("Saved Tabs") { perform(.file(.saved)) }
            if let space = browser.space(matching: request.assignment) {
                ForEach(space.folderTree.flattenedNodes(collapsedFolderIDs: [])) { node in
                    Button(space.folderTree.pathTitle(for: node.id) ?? node.folder.title) {
                        perform(.file(node.folder.location.tabPlacement, folder: node.id))
                    }
                }
            }
        }
        Menu("Move to Space", systemImage: "square.grid.2x2") {
            ForEach(
                BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
                    from: request.assignment, in: browser, accessController: spaceAccess)
            ) { space in
                Button {
                    perform(.moveToSpace(BrowserSpaceRuntimeAssignment(space: space)))
                } label: {
                    BrowserSpaceIdentityLabel(space: space)
                }
            }
        }
        Button("Combine in Split View", systemImage: "rectangle.split.2x1") { perform(.split()) }
        if request.members.contains(where: { $0.splitGroupID != nil }) {
            Button("Separate Selected Splits", systemImage: "rectangle.split.2x1.slash") { perform(.separateSplits) }
        }
        Divider()
        Button("Keep Pages Loaded", systemImage: "lock") { perform(.keepLoaded(true)) }
        Button("Stop Keeping Pages Loaded", systemImage: "lock.open") { perform(.keepLoaded(false)) }
        Button("Duplicate \(count) Tabs", systemImage: "plus.square.on.square") { perform(.duplicate) }
        if let unload {
            Button("Unload \(count) Pages", systemImage: "minus") {
                do {
                    try actions.validate(request, action: .keepLoaded(false))
                    for id in request.ids { unload(id) }
                    browser.tabMultiSelection.clear()
                } catch { browser.tabMultiSelection.message = actions.message(for: error) }
            }
        }
        Button("Archive Selected Tabs", systemImage: "archivebox") { perform(.close) }
        Button("Delete \(count) Tabs", systemImage: "trash", role: .destructive) { perform(.delete) }
        Divider()
        Button("Select All Tabs") {
            browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser))
        }
        Button("Deselect All") { browser.tabMultiSelection.clear() }
    }

    private var folderMenu: some View {
        Group {
            Group {
                if request.rootItems.count == 1 {
                    Text("1 item selected")
                } else {
                    Text("\(request.rootItems.count) items selected")
                }
            }
            .disabled(true)
            Divider()
            Button("Move to Current Tabs", systemImage: "rectangle.stack") { perform(.file(.current)) }
            Button("Move to Saved Tabs", systemImage: "bookmark") { perform(.file(.saved)) }
            Menu("Move to Folder", systemImage: "folder") {
                Button("New Current Tabs Folder") { perform(.newFolder(.current)) }
                Button("New Saved Folder") { perform(.newFolder(.saved)) }
                if let space = browser.space(matching: request.assignment) {
                    ForEach(
                        space.folderTree.flattenedNodes(collapsedFolderIDs: []).filter {
                            !request.folderIDs.contains($0.id)
                        }
                    ) { node in
                        Button(space.folderTree.pathTitle(for: node.id) ?? node.folder.title) {
                            perform(.file(node.folder.location.tabPlacement, folder: node.id))
                        }
                    }
                }
            }
            Divider()
            Button("Select All Items") {
                browser.tabMultiSelection.selectAll(units: BrowserSidebarSelection.itemUnits(in: browser))
            }
            Button("Deselect All") { browser.tabMultiSelection.clear() }
        }
    }

    private func perform(_ action: BrowserTabBatchAction) { actions.perform(request, action: action) }

    private func copyLinks() { actions.copyLinks(request) }
}
