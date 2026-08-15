import Observation

@Observable
@MainActor
final class BrowserSpaceSettingsPresentationState {
    private(set) var requestedDestination = BrowserSettingsDestination.spaces
    private(set) var requestedAssignment: BrowserSpaceRuntimeAssignment?
    private(set) var requestedExtensionCommand: BrowserExtensionCommandSettingsRoute?
    private(set) var revision = 0

    var requestedSpaceID: SpaceID? { requestedAssignment?.spaceID }

    func present(assignment: BrowserSpaceRuntimeAssignment) {
        present(.spaces, assignment: assignment)
    }

    func present(
        _ destination: BrowserSettingsDestination,
        assignment: BrowserSpaceRuntimeAssignment
    ) {
        requestedDestination = destination
        requestedAssignment = assignment
        requestedExtensionCommand = nil
        revision &+= 1
    }

    func presentExtensionCommandSettings(
        _ route: BrowserExtensionCommandSettingsRoute,
        assignment: BrowserSpaceRuntimeAssignment
    ) {
        requestedDestination = .shortcuts
        requestedAssignment = assignment
        requestedExtensionCommand = route
        revision &+= 1
    }

    func requestedSpaceID(in browser: BrowserStore) -> SpaceID? {
        guard let requestedAssignment else { return nil }
        return browser.space(matching: requestedAssignment)?.id
    }
}
