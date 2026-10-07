import Foundation
import Observation

/// A request from elsewhere in the app to show a Settings page: a settings
/// destination, or one page of a Space's settings.
enum BrowserSettingsRequest: Equatable, Sendable {
    case destination(BrowserSettingsDestination)
    case space(BrowserSpaceSettingsTab, intent: BrowserSettingsSpaceIntent = .none)

    /// The request for `destination`. A destination whose subject belongs to
    /// one Space opens that Space's page.
    init(_ destination: BrowserSettingsDestination) {
        self = BrowserSpaceSettingsTab.holding(destination).map { .space($0) } ?? .destination(destination)
    }
}

@Observable
@MainActor
final class BrowserSpaceSettingsPresentationState {
    private(set) var request = BrowserSettingsRequest.space(.appearance)
    private(set) var requestedAssignment: BrowserSpaceRuntimeAssignment?
    /// The search the request carries over from the Settings tab it came from.
    private(set) var searchText: String?
    private(set) var revision = 0

    var requestedSpaceID: UUID? { requestedAssignment?.spaceID }

    func present(assignment: BrowserSpaceRuntimeAssignment) {
        present(.space(.appearance), assignment: assignment)
    }

    func present(
        _ destination: BrowserSettingsDestination,
        assignment: BrowserSpaceRuntimeAssignment
    ) {
        present(BrowserSettingsRequest(destination), assignment: assignment)
    }

    func present(
        _ request: BrowserSettingsRequest,
        assignment: BrowserSpaceRuntimeAssignment,
        searchText: String? = nil
    ) {
        self.request = request
        requestedAssignment = assignment
        self.searchText = searchText
        revision &+= 1
    }

    func requestedSpaceID(in browser: BrowserStore) -> UUID? {
        guard let requestedAssignment else { return nil }
        return browser.spaceModel(matching: requestedAssignment)?.id
    }
}
