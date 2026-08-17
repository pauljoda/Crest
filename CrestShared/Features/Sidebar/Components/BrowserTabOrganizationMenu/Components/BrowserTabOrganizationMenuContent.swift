import SwiftUI

struct BrowserTabOrganizationMenuContent: View {
    let tab: BrowserTab
    let assignment: BrowserTabRuntimeAssignment
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    var isLoaded = true
    var unload: ((TabID) -> Void)? = nil
    var pullNewIcon: (() -> Void)? = nil
    var restoreSavedLocation: (() -> Void)? = nil
    var renameTab: (() -> Void)? = nil

    @Environment(\.layoutDirection) private var layoutDirection

    init(menu: BrowserTabOrganizationMenu) {
        tab = menu.tab
        assignment = menu.assignment
        browser = menu.browser
        spaceAccess = menu.spaceAccess
        isLoaded = menu.isLoaded
        unload = menu.unload
        pullNewIcon = menu.pullNewIcon
        restoreSavedLocation = menu.restoreSavedLocation
        renameTab = menu.renameTab
    }

    var body: some View {
        if let renameTab {
            Button("Rename Tab…", systemImage: "pencil") {
                performIfCurrent { _ in renameTab() }
            }

            Divider()
        }

        if !tab.isStartPage {
            BrowserTabEditActions(
                tab: tab,
                isLoaded: isLoaded,
                pullNewIcon: pullNewIcon,
                restoreSavedLocation: restoreSavedLocation,
                performIfCurrent: performIfCurrent,
                replaceSavedLocation: { liveTab in
                    browser.replaceTabSavedLocationWithCurrent(
                        liveTab.id,
                        in: assignment.spaceID
                    )
                },
                clearIcon: { liveTab in
                    browser.clearTabIcon(
                        for: liveTab.id,
                        matching: sourceAssignment
                    )
                },
                setEmoji: { liveTab, emoji in
                    browser.setTabEmojiIcon(
                        emoji,
                        for: liveTab.id,
                        matching: sourceAssignment
                    )
                }
            )

            Divider()
        }

        if tab.placement != .pinned {
            Button("Pin Tab", systemImage: "pin") {
                performIfCurrent { liveTab in
                    browser.moveTab(
                        liveTab.id,
                        matching: sourceAssignment,
                        to: .pinned
                    )
                }
            }
        }

        Menu("Save in Folder", systemImage: "folder") {
            Button("Saved Tabs", systemImage: "bookmark") {
                performIfCurrent { liveTab in
                    browser.moveTab(
                        liveTab.id,
                        matching: sourceAssignment,
                        to: .saved
                    )
                }
            }
            .disabled(tab.placement == .saved && tab.folderID == nil)

            if let space = browser.space(matching: sourceAssignment),
                !space.folders.isEmpty
            {
                Divider()
                let tree = space.folderTree
                ForEach(tree.flattenedNodes(collapsedFolderIDs: [])) { node in
                    Button(
                        tree.pathTitle(for: node.id) ?? node.folder.title,
                        systemImage: node.folder.symbol
                    ) {
                        performIfCurrent { liveTab in
                            browser.moveTab(
                                liveTab.id,
                                matching: sourceAssignment,
                                to: .saved,
                                folderID: node.id
                            )
                        }
                    }
                    .disabled(tab.placement == .saved && tab.folderID == node.id)
                }
            }
        }

        if tab.placement != .current {
            Button("Move to Current Tabs", systemImage: "rectangle.stack") {
                performIfCurrent { liveTab in
                    browser.moveTab(
                        liveTab.id,
                        matching: sourceAssignment,
                        to: .current
                    )
                }
            }
        }

        let otherSpaces = availableDestinationSpaces
        if !otherSpaces.isEmpty {
            Menu("Move to Space", systemImage: "square.grid.2x2") {
                ForEach(otherSpaces) { space in
                    Button {
                        performIfCurrent { liveTab in
                            let destinationAssignment =
                                BrowserSpaceRuntimeAssignment(space: space)
                            guard
                                BrowserSidebarAccessPolicy.unlockedSpace(
                                    matching: destinationAssignment,
                                    in: browser,
                                    accessController: spaceAccess
                                ) != nil
                            else { return }
                            browser.moveTab(
                                liveTab.id,
                                matching: sourceAssignment,
                                into: destinationAssignment
                            )
                        }
                    } label: {
                        BrowserSpaceIdentityLabel(space: space)
                    }
                    .disabled(
                        !browser.canMoveTab(
                            assignment.tabID,
                            matching: sourceAssignment,
                            into: BrowserSpaceRuntimeAssignment(space: space)
                        )
                    )
                }
            }
            .tint(.primary)
        }

        Divider()

        Button("Split with Current Tab", systemImage: "rectangle.split.2x1") {
            performIfCurrent { liveTab in
                browser.splitTabWithSelectedTab(
                    liveTab.id,
                    matching: sourceAssignment
                )
            }
        }
        .disabled(
            !browser.canSplitTabWithSelectedTab(
                assignment.tabID,
                matching: sourceAssignment
            )
        )

        if isRenderableSplitMember {
            moveButton(.left, title: "Move Left", systemImage: "arrow.left")
            moveButton(.right, title: "Move Right", systemImage: "arrow.right")

            Button("Remove from Split", systemImage: "rectangle.badge.minus") {
                performIfCurrent { liveTab in
                    browser.removeTabFromSplit(
                        liveTab.id,
                        matching: sourceAssignment
                    )
                }
            }
        }

        Divider()

        Button(
            tab.keepsPageLoaded ? "Stop Keeping Loaded" : "Keep Loaded",
            systemImage: tab.keepsPageLoaded ? "lock.open" : "lock"
        ) {
            performIfCurrent { liveTab in
                browser.setTabKeepsPageLoaded(
                    !liveTab.keepsPageLoaded,
                    for: liveTab.id,
                    matching: sourceAssignment
                )
            }
        }

        if let unload, isLoaded {
            Button("Unload Tab", systemImage: "minus") {
                performIfCurrent { liveTab in
                    unload(liveTab.id)
                }
            }
        }

        Button("Duplicate Tab", systemImage: "plus.square.on.square") {
            performIfCurrent { liveTab in
                browser.duplicateTab(
                    liveTab.id,
                    matching: sourceAssignment
                )
            }
        }

        Button(
            tab.placement == .current ? "Close Tab" : "Delete Tab",
            systemImage: tab.placement == .current ? "xmark" : "trash",
            role: .destructive
        ) {
            performIfCurrent { liveTab in
                if tab.placement == .current {
                    organizationAction.close(
                        liveAssignment(for: liveTab),
                        expectedPlacement: tab.placement
                    )
                } else {
                    organizationAction.delete(
                        liveAssignment(for: liveTab),
                        expectedPlacement: tab.placement
                    )
                }
            }
        }
    }

    /// One "Move Left"/"Move Right" item, dimmed once the card is at that end.
    ///
    /// The card at the end of the run keeps the item rather than losing it: a
    /// pair of reordering items that appear and disappear as the card travels
    /// would make the menu jump under the pointer. "Remove from Split" is
    /// absent-or-present because it answers a different question — whether this
    /// row is in a split at all.
    private func moveButton(
        _ direction: BrowserSplitCardMoveDirection,
        title: LocalizedStringKey,
        systemImage: String
    ) -> some View {
        let offset = direction.memberOffset(layoutDirection: layoutDirection)
        return Button(title, systemImage: systemImage) {
            performIfCurrent { liveTab in
                browser.moveSplitMember(
                    liveTab.id,
                    by: offset,
                    matching: sourceAssignment
                )
            }
        }
        .disabled(
            !browser.canMoveSplitMember(
                assignment.tabID,
                by: offset,
                matching: sourceAssignment
            )
        )
    }

    private var sourceAssignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }

    /// Whether this tab sits in a split the sidebar actually draws as a group.
    ///
    /// Membership alone is not enough: a run shorter than the renderable
    /// minimum keeps its group ID in storage so a staggered sync can
    /// reconstitute the split, but presents as a plain tab. Offering to leave a
    /// group nobody can see would be an action with no visible subject, so the
    /// item is absent rather than dimmed — every other tab in the list is a
    /// tab this menu can act on the same way.
    private var isRenderableSplitMember: Bool {
        browser.space(matching: sourceAssignment)?
            .splitGroup(containing: assignment.tabID) != nil
    }

    private var availableDestinationSpaces: [BrowserSpace] {
        BrowserSidebarAccessPolicy.availableTabMoveDestinationSpaces(
            from: sourceAssignment,
            in: browser,
            accessController: spaceAccess
        )
    }

    private func performIfCurrent(_ action: (BrowserTab) -> Void) {
        guard
            let space = BrowserSidebarAccessPolicy.selectedUnlockedSpace(
                matching: sourceAssignment,
                in: browser,
                accessController: spaceAccess
            ),
            let liveTab = space.tabs.first(where: {
                $0.id == assignment.tabID
            })
        else { return }
        action(liveTab)
    }

    private var organizationAction: BrowserTabOrganizationAction {
        BrowserTabOrganizationAction(
            browser: browser,
            spaceAccess: spaceAccess
        )
    }

    private func liveAssignment(
        for liveTab: BrowserTab
    ) -> BrowserTabRuntimeAssignment {
        BrowserTabRuntimeAssignment(
            tabID: liveTab.id,
            spaceID: assignment.spaceID,
            profileID: assignment.profileID
        )
    }
}
