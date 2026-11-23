import SwiftUI

/// A page of Site Controls over the root: Back, the page's title over the
/// site's host on a page about the site, Edit and Done on a page that edits
/// what it lists, as round glass buttons, and the page's rows,
/// which scroll within the root's height.
struct SiteControlsPageView<ExtensionsPage: View>: View {
    let model: SiteControlsModel
    let page: SiteControlsPage
    let extensionsPage: () -> ExtensionsPage

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            header
            router.pinned
            ScrollView {
                router
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, metrics.padding)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding([.top, .horizontal], metrics.padding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private var router: SiteControlsPageRouter<ExtensionsPage> {
        SiteControlsPageRouter(model: model, page: page, extensionsPage: extensionsPage)
    }

    private var title: LocalizedStringResource {
        model.isEditingActions ? page.editingTitle ?? page.title : page.title
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .font(metrics.pageTitleFont)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                if page.isAboutSite, let host = model.host {
                    Text(verbatim: host)
                        .font(metrics.detailFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, metrics.glassIconSize + CrestSpacing.medium)
            HStack {
                SiteControlsGlassIconButton(title: "Back", symbol: "chevron.left") { model.back() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("site-controls-back")
                Spacer()
                if page.editingTitle != nil {
                    SiteControlsGlassIconButton(
                        title: model.isEditingActions ? "Done" : "Edit",
                        symbol: model.isEditingActions ? "checkmark" : "pencil",
                        isProminent: model.isEditingActions
                    ) {
                        model.isEditingActions.toggle()
                        model.selectedSlot = 0
                    }
                    .accessibilityIdentifier("site-controls-edit-toggle")
                }
            }
        }
        .frame(minHeight: metrics.glassIconSize + 4)
    }
}
