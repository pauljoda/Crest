import SwiftUI

struct BrowserSpacePageSurface: NSViewRepresentable {
    let model: BrowserRootModel
    let tabPromotionNamespace: Namespace.ID
    var appearance = BrowserChromeAppearance()

    @AppStorage(SpacePageMotionPreference.key)
    private var animatesSpacePages = SpacePageMotionPreference.defaultValue

    func makeNSView(context: Context) -> SpaceContentPagerView<BrowserRootPageSurface> {
        SpaceContentPagerView(frame: .zero)
    }

    func updateNSView(_ view: SpaceContentPagerView<BrowserRootPageSurface>, context: Context) {
        view.update(
            spaces: BrowserSidebarAccessPolicy.availableSpaces(in: model.browser),
            selectedSpaceID: model.browser.session.selectedSpaceID,
            lockedSpaceIDs: model.lockedSpaceIDs,
            layoutDirection: context.environment.layoutDirection,
            presentation: animatesSpacePages && !context.environment.accessibilityReduceMotion
                ? context.environment.spacePagerPresentation : nil
        ) { space, isSelected in
            SpacePageRoot(
                content: BrowserRootPageSurface(
                    model: model, space: space, isSelectedSpace: isSelected,
                    tabPromotionNamespace: tabPromotionNamespace,
                    appearance: appearance,
                    layoutDirection: context.environment.layoutDirection),
                assignment: BrowserSpaceRuntimeAssignment(space: space))
        }
    }

    static func dismantleNSView(_ view: SpaceContentPagerView<BrowserRootPageSurface>, coordinator: ()) {
        view.disconnect()
    }
}
