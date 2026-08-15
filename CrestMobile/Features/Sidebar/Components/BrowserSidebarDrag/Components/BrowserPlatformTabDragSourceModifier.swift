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

    private var item: BrowserTabDragItem {
        BrowserTabDragItem(tabID: tab.id, spaceID: spaceID, profileID: profileID)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if let reorder {
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
                .onDrag {
                    reorder.state.stage(
                        item: .tab(item),
                        section: .tabs(
                            placement: tab.placement,
                            folderID: tab.folderID
                        )
                    )
                    let payload = (try? JSONEncoder().encode(item)) ?? Data()
                    return NSItemProvider(
                        item: payload as NSData,
                        typeIdentifier: UTType.json.identifier
                    )
                } preview: {
                    BrowserTabDragPreview(
                        tab: tab,
                        profileID: profileID,
                        progress: BrowserTabDragPreviewLayout.progress(
                            for: tab.placement
                        )
                    )
                }
                .modifier(
                    BrowserMobileReorderSessionModifier(state: reorder.state)
                )
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

#Preview("Mobile Tab Drag Source", traits: .sizeThatFitsLayout) {
    let fixture = BrowserSidebarInteractionPreviewFixture()
    let dragState = fixture.makeTabDragState(tab: fixture.currentTab)

    Label(fixture.currentTab.displayTitle, systemImage: "doc.text.fill")
        .frame(width: 220, alignment: .leading)
        .padding(CrestSpacing.medium)
        .background(CrestColor.selectedSurface, in: .rect(cornerRadius: 10))
        .modifier(
            BrowserPlatformTabDragSourceModifier(
                tab: fixture.currentTab,
                profileID: fixture.space.profile.id,
                spaceID: fixture.space.id,
                dragState: dragState
            )
        )
        .padding()
}
