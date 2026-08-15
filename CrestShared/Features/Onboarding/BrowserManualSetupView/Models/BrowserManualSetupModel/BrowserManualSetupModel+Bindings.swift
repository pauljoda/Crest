import SwiftUI

extension BrowserManualSetupModel {
    func nameBinding(
        for spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) -> Binding<String> {
        Binding(
            get: { self.draft(spaceID, in: plan.wrappedValue)?.customization.name ?? "" },
            set: { value in
                plan.wrappedValue.setSpaceIdentity(
                    name: value,
                    symbol: self.draft(spaceID, in: plan.wrappedValue)?
                        .customization.symbol ?? "square.grid.2x2",
                    for: spaceID
                )
            }
        )
    }

    func symbolBinding(
        for spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) -> Binding<String> {
        Binding(
            get: {
                self.draft(spaceID, in: plan.wrappedValue)?
                    .customization.symbol ?? "square.grid.2x2"
            },
            set: { value in
                plan.wrappedValue.setSpaceIdentity(
                    name: self.draft(spaceID, in: plan.wrappedValue)?
                        .customization.name ?? "Untitled Space",
                    symbol: value,
                    for: spaceID
                )
            }
        )
    }

    func brandingBinding(
        for spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) -> Binding<BrowserSpaceBranding> {
        Binding(
            get: {
                self.draft(spaceID, in: plan.wrappedValue)?
                    .customization.branding
                    ?? .initial(
                        accent: .indigo,
                        symbol: "square.grid.2x2"
                    )
            },
            set: {
                plan.wrappedValue.setSpaceBranding($0, for: spaceID)
            }
        )
    }
}
