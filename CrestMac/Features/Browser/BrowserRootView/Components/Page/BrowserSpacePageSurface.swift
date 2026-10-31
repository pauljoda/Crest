import SwiftUI

struct BrowserSpacePageSurface: NSViewRepresentable {
    let model: BrowserRootModel
    let transientBrowsing: BrowserTransientBrowsingCoordinator
    let tabPromotionNamespace: Namespace.ID
    let shortcuts: BrowserShortcutStore?

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue
    private var pageEnvironment = SpacePageEnvironment()

    func makeNSView(context: Context) -> SpaceContentPagerView<BrowserRootPageSurface> {
        SpaceContentPagerView(frame: .zero)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: SpaceContentPagerView<BrowserRootPageSurface>, context: Context
    ) -> CGSize? {
        // The shell determines the content area; retained pages fill it.
        // Native fitting would walk every retained page's subtree, every
        // Settings row among them, whenever a page's scroll geometry changes.
        proposal.replacingUnspecifiedDimensions(by: .zero)
    }

    func updateNSView(_ view: SpaceContentPagerView<BrowserRootPageSurface>, context: Context) {
        let objects = pageEnvironment.objects
        view.update(
            spaces: model.browser.availableSpaces,
            selectedSpaceID: model.browser.selectedSpaceID,
            lockedSpaceIDs: model.lockedSpaceIDs,
            shownPins: shownPins,
            layoutDirection: context.environment.layoutDirection,
            presentation: animatesSpacePages && !context.environment.accessibilityReduceMotion
                ? context.environment.spacePagerPresentation : nil
        ) { space, isSelected in
            SpacePageRoot(
                content: BrowserRootPageSurface(
                    model: model, space: space, isSelectedSpace: isSelected,
                    transientBrowsing: transientBrowsing,
                    tabPromotionNamespace: tabPromotionNamespace,
                    shortcuts: shortcuts,
                    layoutDirection: context.environment.layoutDirection),
                assignment: BrowserSpaceRuntimeAssignment(space: space), objects: objects)
        }
    }

    static func dismantleNSView(_ view: SpaceContentPagerView<BrowserRootPageSurface>, coordinator: ()) {
        view.disconnect()
    }

    /// The pinned tab each open Space shows in this window, for those that
    /// show one rather than another tab or a Start Page on entry.
    private var shownPins: [UUID: UUID] {
        let browser = model.browser
        var pins: [UUID: UUID] = [:]
        for space in browser.availableSpaces where !model.lockedSpaceIDs.contains(space.id) {
            guard space.id == browser.selectedSpaceID || !model.pages.requiresStartPageOnEntry(to: space),
                let tabID = browser.selectedTabID(in: space.id), space.shownTab(tabID)?.placement == .pinned
            else { continue }
            pins[space.id] = tabID
        }
        return pins
    }
}
