import Foundation

/// A request to show a settings destination.
struct BrowserSettingsDestinationRequest: BrowserSettingsRequest {
    // MARK: - Variables

    let destination: BrowserSettingsDestination
    var section: BrowserSettingsSection?
    var pictureInPicturePreviewSpace: BrowserSpaceRuntimeAssignment?

    // MARK: - Actions - Route

    @MainActor
    func apply(to tabState: BrowserSettingsTabState, spaceID: UUID?) {
        tabState.navigation.selection = .destination(destination)
        tabState.requestedSection = section
        tabState.pictureInPicturePreviewSpace = pictureInPicturePreviewSpace
    }
}
