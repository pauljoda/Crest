import SwiftUI

/// What the site keeps in the page's Space, which each row clears before the
/// page reloads.
struct SiteControlsSiteDataPage: View {
    let model: SiteControlsModel

    var body: some View {
        SiteControlsPageSection {
            row(.clearCookies, subtitle: Text("Signs you out of this site"))
            row(.clearCache, subtitle: nil)
        }
    }

    private func row(_ action: SiteControlAction, subtitle: Text?) -> some View {
        let item = model.item(action)
        return SiteControlsRow(title: Text(item.title), symbol: item.symbol, subtitle: subtitle) {
            model.run(action)
        } trailing: {
            EmptyView()
        }
        .disabled(!item.state.isAvailable)
        .accessibilityIdentifier("site-control-\(action.name)")
    }
}
