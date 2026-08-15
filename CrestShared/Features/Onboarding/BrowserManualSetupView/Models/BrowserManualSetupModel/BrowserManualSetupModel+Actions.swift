import SwiftUI

extension BrowserManualSetupModel {
    func repairSelection(
        plan: BrowserManualSetupPlan,
        selectedSpaceID: Binding<SpaceID?>
    ) {
        guard
            !plan.spaces.contains(where: {
                $0.id == selectedSpaceID.wrappedValue
            })
        else { return }
        selectedSpaceID.wrappedValue = plan.spaces.first?.id
    }

    func select(
        _ spaceID: SpaceID,
        selectedSpaceID: Binding<SpaceID?>
    ) {
        selectedSpaceID.wrappedValue = spaceID
        errorMessage = nil
    }

    func addSpace(
        plan: Binding<BrowserManualSetupPlan>,
        selectedSpaceID: Binding<SpaceID?>
    ) {
        do {
            let spaceID = try plan.wrappedValue.addSpace()
            select(spaceID, selectedSpaceID: selectedSpaceID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSpace(
        _ spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) {
        _ = plan.wrappedValue.removeSpace(spaceID)
    }

    func addTab(
        to spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) {
        do {
            _ = try plan.wrappedValue.addTab(
                input: address,
                placement: placement,
                to: spaceID
            )
            address = ""
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addSuggestion(
        _ suggestion: BrowserSetupSiteSuggestion,
        to spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) {
        do {
            _ = try plan.wrappedValue.addTab(
                title: suggestion.title,
                url: suggestion.url,
                placement: suggestion.defaultPlacement,
                to: spaceID
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeTab(
        _ tabID: TabID,
        from spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) {
        _ = plan.wrappedValue.removeTab(tabID, from: spaceID)
    }

    func setPlacement(
        _ placement: TabPlacement,
        for tabID: TabID,
        in spaceID: SpaceID,
        plan: Binding<BrowserManualSetupPlan>
    ) {
        do {
            try plan.wrappedValue.setPlacement(
                placement,
                for: tabID,
                in: spaceID
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
