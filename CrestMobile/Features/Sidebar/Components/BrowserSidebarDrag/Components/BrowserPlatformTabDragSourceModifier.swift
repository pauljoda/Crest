import SwiftUI
import UniformTypeIdentifiers

struct BrowserPlatformTabDragSourceModifier: ViewModifier {
    let tab: BrowserTab
    let profileID: UUID
    let spaceID: SpaceID
    let dragState: BrowserTabDragState
    var reorder: BrowserSidebarReorderContext?

    @State private var sessionToken: BrowserDragSessionToken?
    @State private var sourceSize = CGSize.zero
    @Environment(\.colorScheme) private var colorScheme

    private var item: BrowserTabDragItem {
        BrowserTabDragItem(tabID: tab.id, spaceID: spaceID, profileID: profileID)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
            let shape = reorder.state.liftTargetShape ?? .resting(for: tab.placement)
            // The lift comes from drag-and-drop, not a gesture: a row carries a
            // context menu, and UIKit cancels a competing gesture the moment the
            // menu claims the touch. Holding still opens the menu, pulling lifts
            // the row — the pairing the system already arbitrates.
            content
                .browserSidebarReorderSource(
                    item: .tab(item),
                    section: .tabs(
                        placement: tab.placement,
                        folderID: tab.folderID
                    ),
                    reorder: reorder
                )
                .browserMobileDraggable(previewShape: shape) {
                    reorder.state.stage(
                        item: .tab(item),
                        section: .tabs(
                            placement: tab.placement,
                            folderID: tab.folderID
                        )
                    )
                    let payload = (try? JSONEncoder().encode(item)) ?? Data()
                    let provider = NSItemProvider(
                        item: payload as NSData,
                        typeIdentifier: UTType.json.identifier
                    )
                    let token = reorder.state.sessionToken
                    return BrowserMobileDragSession(provider: provider) {
                        guard let token else { return }
                        reorder.state.cancel(session: token)
                    }
                } preview: { sourceWidth in
                    BrowserTabDragPreview(
                        tab: tab,
                        profileID: profileID,
                        targetShape: shape,
                        progress: shape == .row ? 0 : 1,
                        rowWidth: tab.placement == .pinned
                            ? BrowserTabDragPreviewLayout.defaultRowWidth : sourceWidth,
                        rowMetrics: .touch
                    )
                    .environment(\.colorScheme, colorScheme)
                }
        } else {
            legacyDraggable(content)
        }
    }

    @ViewBuilder
    private func legacyDraggable(_ content: Content) -> some View {
        let draggableContent =
            content
            .onDrag {
                let item = BrowserTabDragItem(
                    tabID: tab.id,
                    spaceID: spaceID,
                    profileID: profileID
                )
                sessionToken = dragState.begin(
                    item: item,
                    placement: tab.placement
                )
                let data = (try? JSONEncoder().encode(item)) ?? Data()
                return NSItemProvider(
                    item: data as NSData,
                    typeIdentifier: UTType.json.identifier
                )
            } preview: {
                BrowserTabReactiveDragPreview(
                    tab: tab,
                    profileID: profileID,
                    dragState: dragState
                )
                .environment(\.colorScheme, colorScheme)
            }

        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                draggableContent
                    .onDragSessionUpdated { session in
                        let lifecyclePhase: BrowserTabDragSessionLifecyclePhase =
                            switch session.phase {
                            case .ended:
                                .ended
                            case .dataTransferCompleted:
                                .dataTransferCompleted
                            default:
                                .active
                            }
                        guard
                            BrowserTabDragSessionLifecyclePolicy.shouldEnd(
                                for: lifecyclePhase
                            )
                        else { return }
                        Task { @MainActor in
                            guard let sessionToken else { return }
                            dragState.end(session: sessionToken)
                        }
                    }
            } else {
                draggableContent
            }
        #else
            draggableContent
        #endif
    }
}
