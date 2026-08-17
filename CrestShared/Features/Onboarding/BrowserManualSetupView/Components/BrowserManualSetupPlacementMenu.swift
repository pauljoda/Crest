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
            ForEach(
                BrowserManualSetupPlacementPresentation.choices,
                id: \.self
            ) { placement in
                Button(
                    BrowserManualSetupPlacementPresentation.title(
                        for: placement
                    ),
                    systemImage: BrowserManualSetupPlacementPresentation.symbol(
                        for: placement
                    )
                ) {
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
        } label: {
            BrowserManualSetupPlacementMenuLabel(
                placement: tab.placement,
                symbol: labelSymbol
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(
            Text(
                BrowserManualSetupPlacementPresentation.label(
                    for: tab.placement
                )
            )
        )
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
