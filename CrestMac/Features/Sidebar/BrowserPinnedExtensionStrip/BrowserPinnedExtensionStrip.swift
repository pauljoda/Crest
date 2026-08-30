import AppKit
import SwiftUI

struct BrowserPinnedExtensionStrip: View {
    let spaceID: SpaceID
    let selectedTabID: TabID?
    let extensionControllerPool: BrowserExtensionControllerPool
    private let actionPresentationOverride: [BrowserExtensionActionPresentation]?

    init(
        spaceID: SpaceID,
        selectedTabID: TabID?,
        extensionControllerPool: BrowserExtensionControllerPool,
        actionPresentationOverride: [BrowserExtensionActionPresentation]? = nil
    ) {
        self.spaceID = spaceID
        self.selectedTabID = selectedTabID
        self.extensionControllerPool = extensionControllerPool
        self.actionPresentationOverride = actionPresentationOverride
    }

    @ViewBuilder
    var body: some View {
        if !presentedActions.isEmpty {
            BrowserPinnedExtensionStripContent(
                actions: presentedActions,
                perform: perform,
                prepare: prepare,
                presentMenu: presentMenu
            )
        }
    }

    private var toolbarActions: [BrowserExtensionToolbarAction] {
        extensionControllerPool.toolbarActions(
            in: spaceID,
            tabID: selectedTabID
        )
        .filter(\.isPinned)
    }

    private var presentedActions: [BrowserExtensionActionPresentation] {
        actionPresentationOverride
            ?? toolbarActions.map(BrowserExtensionActionPresentation.init(action:))
    }

    private func presentMenu(
        _ presentation: BrowserExtensionActionPresentation,
        anchor: BrowserExtensionPopupAnchor?
    ) {
        guard
            let action = toolbarActions.first(where: {
                $0.id == presentation.id
            })
        else { return }
        BrowserExtensionContextMenu.present(
            for: action,
            pool: extensionControllerPool,
            spaceID: spaceID,
            anchor: anchor
        )
    }

    private func perform(
        _ presentation: BrowserExtensionActionPresentation,
        popupAnchor: BrowserExtensionPopupAnchor?
    ) {
        guard
            let action = toolbarActions.first(where: {
                $0.id == presentation.id
            })
        else { return }
        extensionControllerPool.perform(
            action,
            popupAnchor: popupAnchor
                ?? BrowserExtensionPopupAnchor(
                    screenPoint:
                        BrowserPinnedExtensionStripLayoutPolicy.popupAnchor(
                            below: NSEvent.mouseLocation
                        ),
                    sourceWindow: NSApp.keyWindow
                )
        )
    }

    private func prepare(
        _ presentation: BrowserExtensionActionPresentation
    ) {
        guard
            let action = toolbarActions.first(where: {
                $0.id == presentation.id
            })
        else { return }
        extensionControllerPool.prepare(action)
    }

}
