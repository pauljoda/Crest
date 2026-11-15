import Observation
import SwiftUI

/// One Space's download folder on iPhone and iPad. Until the person picks a
/// folder, such as the Downloads folder the Files app shows, files go to
/// Crest's own folder; iOS lets Crest write elsewhere only once they pick it.
@Observable
@MainActor
final class MobileSpaceDownloadSettingsModel {
    // MARK: - Variables

    /// The folder the person chose, or nil while files go to Crest's own.
    private(set) var chosenDirectoryName: String?
    private(set) var errorMessage: String?

    var isChoosingDirectory = false

    @ObservationIgnored private var choosingSpaceID: UUID?

    /// The Space the section last showed, whose error another Space's
    /// section must not show.
    @ObservationIgnored private var shownSpaceID: UUID?

    @ObservationIgnored private let preferences: BrowserPlatformDownloadPreferences

    // MARK: - Initializers

    init(preferences: BrowserPlatformDownloadPreferences = .shared) {
        self.preferences = preferences
    }

    // MARK: - Actions - Settings

    func settings(for space: SpaceModel) -> BrowserSpaceDownloadSettings {
        BrowserSpaceDownloadSettings(
            directoryName: chosenDirectoryName ?? String(localized: "Crest"),
            usesCustomDirectory: chosenDirectoryName != nil,
            errorMessage: errorMessage,
            chooseDirectory: { [self] in chooseDirectory(for: space.id) },
            resetTitle: "Use Crest Folder",
            resetDirectory: { [self] in resetDirectory(for: space.id) }
        )
    }

    func refresh(for spaceID: UUID) {
        if spaceID != shownSpaceID {
            shownSpaceID = spaceID
            errorMessage = nil
        }
        chosenDirectoryName = preferences.directoryDisplayName(for: spaceID)
    }

    // MARK: - Mutators

    private func chooseDirectory(for spaceID: UUID) {
        choosingSpaceID = spaceID
        isChoosingDirectory = true
    }

    func finishChoosing(_ result: Result<URL, any Error>) {
        guard let spaceID = choosingSpaceID else { return }
        choosingSpaceID = nil
        // The section may show another Space by the time the picker answers;
        // the folder still belongs to the Space it was chosen for.
        let isShown = spaceID == shownSpaceID
        do {
            try preferences.rememberDirectory(result.get(), for: spaceID)
            if isShown { errorMessage = nil }
        } catch {
            if isShown { errorMessage = String(localized: "Crest couldn’t keep access to this folder.") }
        }
        if isShown { refresh(for: spaceID) }
    }

    private func resetDirectory(for spaceID: UUID) {
        preferences.clearDirectory(for: spaceID)
        errorMessage = nil
        refresh(for: spaceID)
    }
}
