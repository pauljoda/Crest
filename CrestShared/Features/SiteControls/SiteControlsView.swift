import SwiftUI

/// Site Controls: a control center for the page a window shows, the same in
/// a Mac or iPad popover and in an iPhone sheet. The root shows the actions
/// the person keeps on top, what waits on them, the page's extensions,
/// blocking and toggles, zoom and rows that show their value; each row opens
/// a page over it, with Back, at the root's height.
///
/// The page's extensions come from the shell, which composes the engine that
/// has them: their tiles, given the action that opens the Extensions page,
/// and that page's rows.
struct SiteControlsView<ExtensionTiles: View, ExtensionsPage: View>: View {
    let model: SiteControlsModel
    let extensionTiles: (_ openPage: @escaping () -> Void) -> ExtensionTiles
    let extensionsPage: () -> ExtensionsPage

    @Environment(\.siteControlsMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let page = model.shownPage {
                SiteControlsPageView(model: model, page: page, extensionsPage: extensionsPage)
                    .frame(height: metrics.keepsRootHeight ? model.rootHeight : nil, alignment: .top)
                    .transition(transition(edge: .trailing))
                    .id(page)
            } else if metrics.keepsRootHeight {
                SiteControlsRoot(model: model, extensionTiles: extensionTiles)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { model.rootHeight = $0 }
                    .transition(transition(edge: .leading))
            } else {
                // A sheet shows what fits its height and scrolls to the rest.
                ScrollView {
                    SiteControlsRoot(model: model, extensionTiles: extensionTiles)
                }
                .transition(transition(edge: .leading))
            }
        }
        .frame(width: metrics.width, alignment: .top)
        // The root takes the height its content needs, and a page the
        // root's, so the popover fits what it shows with nothing left over.
        .fixedSize(horizontal: false, vertical: metrics.keepsRootHeight)
        // An action being dragged follows the pointer as its tile, over
        // everything Site Controls show.
        .coordinateSpace(SiteControlsModel.space)
        .overlay(alignment: .topLeading) {
            if let drag = model.drag {
                SiteControlsDragPreview(model: model, drag: drag)
            }
        }
        .animation(CrestMotion.navigation.unlessReducingMotion(reduceMotion), value: model.path)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Site Controls")
    }

    init(
        model: SiteControlsModel,
        @ViewBuilder extensionTiles: @escaping (_ openPage: @escaping () -> Void) -> ExtensionTiles,
        @ViewBuilder extensionsPage: @escaping () -> ExtensionsPage
    ) {
        self.model = model
        self.extensionTiles = extensionTiles
        self.extensionsPage = extensionsPage
    }

    /// Pages slide in from the trailing edge and the root comes back from
    /// the leading one; with Reduce Motion they fade.
    private func transition(edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// The root of Site Controls, top to bottom: who the page is, the
/// actions on top, what waits on the person, extensions, blocking, toggles, zoom and
/// the rows that open pages.
private struct SiteControlsRoot<ExtensionTiles: View>: View {
    let model: SiteControlsModel
    let extensionTiles: (_ openPage: @escaping () -> Void) -> ExtensionTiles

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            SiteControlsHeader(model: model)
            SiteControlsActionTiles(model: model)
            if let item = SiteControlsWaitingItem.Content(model: model) {
                SiteControlsWaitingItem(model: model, content: item)
            }
            if model.platform.offersExtensions {
                SiteControlsExtensionsSection(model: model) {
                    extensionTiles { model.open(.extensions) }
                }
            }
            if model.offersContentBlocking {
                SiteControlsBlockingTile(model: model)
            }
            SiteControlsPageToggles(model: model)
            SiteControlsZoomRow(model: model)
            Divider()
                .overlay(CrestBrandTheme.line)
                .padding(.horizontal, CrestSpacing.extraSmall)
            SiteControlsValueRows(model: model)
        }
        .padding(metrics.padding)
        .fixedSize(horizontal: false, vertical: true)
    }
}

extension SiteControlsView where ExtensionTiles == EmptyView, ExtensionsPage == EmptyView {
    /// Site Controls for a page whose engine has no extensions to add.
    init(model: SiteControlsModel) {
        self.init(model: model) { _ in
            EmptyView()
        } extensionsPage: {
            EmptyView()
        }
    }
}
