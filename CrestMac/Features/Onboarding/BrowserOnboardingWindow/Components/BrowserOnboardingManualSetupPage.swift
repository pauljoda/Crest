import SwiftUI

/// Making the Spaces of the manual setup yours, one at a time, in the look
/// setup chose. Continue goes on to the ready page.
struct BrowserOnboardingManualSetupPage: View {
    let flow: BrowserOnboardingFlow
    @Binding var selectedSpaceID: UUID?
    let back: BrowserOnboardingBackAction
    let advance: () -> Void

    private var setup: BrowserManualSetupModel { flow.manualSetup }

    var body: some View {
        if let draft = setup.space(selectedSpaceID) {
            BrowserOnboardingMakePage(
                look: flow.look,
                branding: setup.brandingBinding(for: draft.spaceID),
                symbol: setup.symbolBinding(for: draft.spaceID),
                name: setup.nameBinding(for: draft.spaceID),
                identity: BrowserSpaceIdentity(draft: draft),
                picker: BrowserOnboardingMakePicker(
                    spaces: setup.previewSpaces,
                    selectedID: draft.spaceID,
                    select: { selectedSpaceID = $0 },
                    add: addSpace,
                    remove: { spaceID in
                        setup.space(spaceID)?.isNew == true ? { setup.removeSpace(spaceID) } : nil
                    }),
                failure: flow.failure?.message ?? setup.errorMessage.map(BrowserOnboardingFailureText.verbatim),
                back: back,
                advanceTitle: Text("Continue"),
                advance: advance
            )
            .id(draft.spaceID)
        } else {
            ContentUnavailableView {
                Label("Create your first Space", systemImage: "square.grid.2x2")
            } actions: {
                Button("Add Space", action: addSpace).buttonStyle(.crestPrimary)
            }
        }
    }

    private func addSpace() {
        if let added = setup.addSpace() { selectedSpaceID = added }
    }
}
