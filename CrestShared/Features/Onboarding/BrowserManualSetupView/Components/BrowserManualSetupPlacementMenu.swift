import SwiftUI

struct BrowserManualSetupPlacementMenu: View {
    @Binding var plan: BrowserManualSetupPlan
    let tab: BrowserTab
    let spaceID: SpaceID
    let labelSymbol: String
    let accessibilityLabel: Text
    let accessibilityIdentifier: String
    let model: BrowserManualSetupModel

    var body: some View {
        Menu {
            Group {
                ForEach(TabPlacement.all, id: \.self) { placement in
                    Button(placement.title, systemImage: placement.symbol) {
                        setPlacement(placement)
                    }
                }
                Divider()
                Button(
                    "Remove",
                    systemImage: "trash",
                    role: .destructive,
                    action: removeTab
                )
            }
            .crestMenuActionLabelStyle()
        } label: {
            BrowserManualSetupPlacementMenuLabel(
                placement: tab.placement,
                symbol: labelSymbol
            )
        }
        .crestMenuActionLabelStyle()
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(tab.placement.title))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func setPlacement(_ placement: TabPlacement) {
        model.setPlacement(
            placement,
            for: tab.id,
            in: spaceID,
            plan: $plan
        )
    }

    private func removeTab() {
        model.removeTab(tab.id, from: spaceID, plan: $plan)
    }
}
