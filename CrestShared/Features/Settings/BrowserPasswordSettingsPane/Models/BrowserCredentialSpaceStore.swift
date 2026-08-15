import SwiftUI

/// The Space-scoped credential work both shells were doing twice.
///
/// Reading a Space's Keychain descriptors, deleting one, turning iCloud
/// synchronization on, and authenticating an export are four operations with four
/// loading flags and five error sentences, and all of it had been written out once in
/// ``BrowserPasswordSettingsPane``'s ancestors on each platform. The sentences differ
/// only where the platform differs — nowhere, as it turned out, which is why the
/// copies had already drifted into "removes synchronized copies *from*" against
/// "*of*" Crest's Keychain item.
@Observable
@MainActor
final class BrowserCredentialSpaceStore {
    private(set) var descriptors: [CredentialDescriptor] = []
    private(set) var isLoading = false
    private(set) var isChangingSynchronization = false
    private(set) var isPreparingExport = false
    /// Which rows are mid-delete, so a row can show its own progress rather than
    /// blanking the whole list.
    private(set) var deletingCredentialIDs: Set<CredentialID> = []
    var errorMessage: String?
    var exportDocument: BrowserCredentialCSVDocument?
    var exportFilename = "Crest Passwords.csv"

    @ObservationIgnored private let browser: BrowserStore

    init(browser: BrowserStore) {
        self.browser = browser
    }

    /// The descriptors that match a query, over the four fields both shells searched.
    func descriptors(matching query: String) -> [CredentialDescriptor] {
        BrowserCredentialSettingsPolicy.filter(descriptors, matching: query)
    }

    func isDeleting(_ descriptor: CredentialDescriptor) -> Bool {
        deletingCredentialIDs.contains(descriptor.id)
    }

    func load(
        in spaceID: SpaceID?,
        accessController: BrowserSpaceAccessController
    ) async {
        guard let spaceID,
              let space = browser.session.space(id: spaceID),
              BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                in: space,
                accessController: accessController
              ) else {
            clearSensitiveData()
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loadedDescriptors = try await browser.savedCredentialDescriptors(in: spaceID)
            guard !Task.isCancelled,
                  let currentSpace = browser.session.space(id: spaceID),
                  BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                    in: currentSpace,
                    accessController: accessController
                  ) else {
                clearSensitiveData()
                return
            }
            descriptors = loadedDescriptors
        } catch {
            guard !Task.isCancelled,
                  let currentSpace = browser.session.space(id: spaceID),
                  BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                    in: currentSpace,
                    accessController: accessController
                  ) else {
                clearSensitiveData()
                return
            }
            descriptors = []
            errorMessage = "Crest couldn’t read this Space’s saved-password metadata."
        }
    }

    func clearSensitiveData() {
        descriptors = []
        deletingCredentialIDs = []
        errorMessage = nil
        exportDocument = nil
    }

    func delete(
        _ descriptor: CredentialDescriptor,
        reloading spaceID: SpaceID?,
        accessController: BrowserSpaceAccessController
    ) {
        guard let space = browser.session.space(id: descriptor.spaceID),
              BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                in: space,
                accessController: accessController
              ) else { return }
        deletingCredentialIDs.insert(descriptor.id)
        errorMessage = nil
        Task { @MainActor in
            defer { deletingCredentialIDs.remove(descriptor.id) }
            do {
                try await browser.deleteCredential(
                    id: descriptor.id,
                    in: descriptor.spaceID
                )
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = "Crest couldn’t delete that password from this Space."
            }
        }
    }

    /// Turning synchronization on or off rewrites the Space's existing Keychain
    /// items, so it is an operation with a progress state and a failure — which is
    /// why it is here rather than among the plain preference bindings.
    func setSynchronization(
        _ enabled: Bool,
        in spaceID: SpaceID,
        accessController: BrowserSpaceAccessController
    ) {
        guard let space = browser.session.space(id: spaceID),
              BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                in: space,
                accessController: accessController
              ) else { return }
        isChangingSynchronization = true
        errorMessage = nil
        Task { @MainActor in
            defer { isChangingSynchronization = false }
            do {
                try await browser.setCrestPasswordSynchronization(enabled, in: spaceID)
                await load(in: spaceID, accessController: accessController)
            } catch {
                errorMessage = "Crest couldn’t update iCloud synchronization."
            }
        }
    }

    func synchronizationBinding(
        in space: BrowserSpace,
        accessController: BrowserSpaceAccessController
    ) -> Binding<Bool> {
        Binding { [browser] in
            browser.liveSpace(space).credentialPreferences
                .syncsCrestPasswordsWithICloud
        } set: { [weak self] enabled in
            self?.setSynchronization(
                enabled,
                in: space.id,
                accessController: accessController
            )
        }
    }

    /// Authenticates, builds the CSV, and reports whether the exporter should open.
    /// The Space is re-checked afterwards because authentication can outlive the
    /// reader's interest in that Space.
    func prepareExport(
        in spaceID: SpaceID,
        accessController: BrowserSpaceAccessController,
        isStillSelected: () -> Bool
    ) async -> Bool {
        guard let space = browser.session.space(id: spaceID),
              BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                in: space,
                accessController: accessController
              ) else { return false }
        isPreparingExport = true
        errorMessage = nil
        defer { isPreparingExport = false }
        do {
            let export = try await BrowserCredentialSensitiveAccess(browser: browser)
                .exportCredentials(in: spaceID)
            guard isStillSelected(),
                  let currentSpace = browser.session.space(id: spaceID),
                  BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                    in: currentSpace,
                    accessController: accessController
                  ) else { return false }
            exportDocument = BrowserCredentialCSVDocument(data: export.data)
            exportFilename = export.filename
            return true
        } catch {
            errorMessage = "Crest couldn’t authenticate and export this Space’s passwords."
            return false
        }
    }

    func reportExportFailure() {
        errorMessage = "Crest couldn’t export those passwords."
    }

    func deletionMessage(
        for descriptor: CredentialDescriptor,
        in space: BrowserSpace?
    ) -> String {
        BrowserCredentialSettingsPolicy.deletionMessage(
            for: descriptor,
            spaceName: space?.name
                ?? browser.session.space(id: descriptor.spaceID)?.name
                ?? "this Space"
        )
    }

    func emptyDescription(isSearching: Bool) -> String {
        BrowserCredentialSettingsPolicy.emptyDescription(isSearching: isSearching)
    }
}
