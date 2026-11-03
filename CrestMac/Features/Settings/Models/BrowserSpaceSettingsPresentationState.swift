import Foundation
import Observation

/// The Settings request last made: the page to show and the Space whose
/// Settings tab shows it.
@Observable
@MainActor
final class BrowserSpaceSettingsPresentationState {
    // MARK: - Static Variables

    /// The number the latest request took, in any window. A Space's Settings
    /// tab is shared by every window over its workspace and outlives each of
    /// them, and it takes only a request newer than the last one it took, so
    /// every window numbers its requests from this one sequence.
    private static var latestRevision = 0

    // MARK: - Variables

    private(set) var request: any BrowserSettingsRequest = BrowserSettingsSpaceRequest(tab: .appearance)
    private(set) var requestedAssignment: BrowserSpaceRuntimeAssignment?
    /// The search the request carries over from the Settings tab it came from.
    private(set) var searchText: String?
    private(set) var revision = 0

    var requestedSpaceID: UUID? { requestedAssignment?.spaceID }

    // MARK: - Actions - Presenting

    func present(assignment: BrowserSpaceRuntimeAssignment) {
        present(BrowserSettingsSpaceRequest(tab: .appearance), assignment: assignment)
    }

    /// Presents `destination`. A destination whose subject belongs to one
    /// Space opens that Space's page.
    func present(
        _ destination: BrowserSettingsDestination,
        assignment: BrowserSpaceRuntimeAssignment
    ) {
        let request: any BrowserSettingsRequest =
            BrowserSpaceSettingsTab.holding(destination).map { BrowserSettingsSpaceRequest(tab: $0) }
            ?? BrowserSettingsDestinationRequest(destination: destination)
        present(request, assignment: assignment)
    }

    func present(
        _ request: any BrowserSettingsRequest,
        assignment: BrowserSpaceRuntimeAssignment,
        searchText: String? = nil
    ) {
        self.request = request
        requestedAssignment = assignment
        self.searchText = searchText
        Self.latestRevision &+= 1
        revision = Self.latestRevision
    }

    // MARK: - Actions - Reading

    func requestedSpaceID(in browser: BrowserStore) -> UUID? {
        guard let requestedAssignment else { return nil }
        return browser.spaceModel(matching: requestedAssignment)?.id
    }
}
