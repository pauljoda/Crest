import SwiftUI

/// The Mac's editor also reaches the Spaces the chosen browser brings in new,
/// whose names and looks the review holds until the import is applied.
extension BrowserSetupSpaceEditor {
    // MARK: - Initializers

    /// The editor for `spaceID`: in the manual setup when it holds the
    /// Space, or else in the review, for a Space the import brings in new.
    init?(flow: BrowserOnboardingFlow, spaceID: UUID) {
        if let editor = BrowserSetupSpaceEditor(setup: flow.manualSetup, spaceID: spaceID) {
            self = editor
            return
        }
        guard let review = flow.reviewSpaces.first(where: { $0.id == spaceID && $0.destinationSpaceID == nil })
        else { return nil }
        func customization() -> SpaceCustomization {
            flow.reviewSpaces.first { $0.id == spaceID }?.customization ?? review.customization
        }
        func customize(_ edit: (inout SpaceCustomization) -> Void) {
            var next = customization()
            edit(&next)
            flow.customize(spaceID, as: next)
        }
        self.init(
            name: Binding(get: { customization().name }, set: { value in customize { $0.name = value } }),
            symbol: Binding(get: { customization().symbol }, set: { value in customize { $0.symbol = value } }),
            branding: Binding(get: { customization().branding }, set: { value in customize { $0.branding = value } }))
    }
}
