import SwiftUI

/// Ads and trackers on the page's site: the Space's switch for the site,
/// Block Element and Show Blocked Elements, and the level every site blocks
/// at, which Settings changes.
struct SiteControlsBlockingPage: View {
    let model: SiteControlsModel

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            if let blocking = model.contentBlocking {
                SiteControlsPageSection(
                    footer: model.platform.space.map {
                        Text("Saved in \($0.identity.name). Other Spaces decide for themselves.")
                    }
                ) {
                    SiteControlsRowLabel(
                        title: Text("Blocking on \(blocking.origin.host)"), symbol: "checkmark.shield",
                        subtitle: blocking.blocks
                            ? Text("Ads and trackers are blocked") : Text("Off. The page reloaded.")
                    ) {
                        SiteControlsSwitch(
                            title: Text(blocking.title),
                            isOn: Binding(
                                get: { blocking.blocks }, set: { _ in model.platform.run(.toggleContentBlocking) })
                        )
                        .disabled(!model.platform.canRun(.toggleContentBlocking))
                    }
                }
            }
            SiteControlsPageSection {
                actionRow(.blockElement)
                if model.blockedElements.exist {
                    actionRow(.showBlockedElements)
                }
                SiteControlsRow(
                    "Blocking Level", symbol: "shield",
                    value: String(localized: model.core.state.filterLists.level.title)
                ) {
                    model.platform.dismiss()
                    model.platform.openSettings(.adBlocking)
                }
                .accessibilityIdentifier("site-control-blocking-level")
            }
        }
    }

    private func actionRow(_ action: SiteControlAction) -> some View {
        let item = model.item(action)
        return SiteControlsRow(title: Text(item.title), symbol: item.symbol) {
            model.run(action)
        } trailing: {
            EmptyView()
        }
        .disabled(!item.state.isAvailable)
    }
}
