import Foundation
import Observation

@Observable
@MainActor
final class MobilePasswordSettingsModel {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let credentials: BrowserCredentialSpaceStore

    var selectedSpaceID: SpaceID?
    var searchText = ""
    var pendingDeletion: CredentialDescriptor?
    var credentialDetailRequest: BrowserCredentialDetailRequest?
    var confirmsPlaintextExport = false
    var isExporting = false

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        credentials = BrowserCredentialSpaceStore(browser: browser)
    }

    var selectedSpace: BrowserSpace? {
        guard let selectedSpaceID else { return nil }
        return browser.session.space(id: selectedSpaceID)
    }

    var filteredDescriptors: [CredentialDescriptor] {
        credentials.descriptors(matching: searchText)
    }

    var canRevealSelectedSpaceData: Bool {
        BrowserSettingsPrivacyPolicy.canRevealSpaceData(
            in: selectedSpace,
            accessController: spaceAccess
        )
    }

    var credentialLoadRequest: BrowserSettingsSpaceDataRequest {
        BrowserSettingsSpaceDataRequest(
            assignment: selectedSpace.map(
                BrowserSpaceRuntimeAssignment.init(space:)
            ),
            canRevealSpaceData: canRevealSelectedSpaceData
        )
    }

    var deletionAlertIsPresented: Bool {
        get { pendingDeletion != nil }
        set {
            if !newValue { pendingDeletion = nil }
        }
    }

    func loadCredentials() async {
        await credentials.load(
            in: selectedSpaceID,
            accessController: spaceAccess
        )
    }

    func handleCredentialLoadRequest(
        previous: BrowserSettingsSpaceDataRequest,
        _ request: BrowserSettingsSpaceDataRequest
    ) {
        if previous.assignment != request.assignment
            || !request.canRevealSpaceData
        {
            clearSensitivePresentation()
        }
    }

    func showDetails(_ descriptor: CredentialDescriptor) {
        guard canRevealSelectedSpaceData,
            let selectedSpace,
            let request = BrowserCredentialDetailRequest(
                descriptor: descriptor,
                space: selectedSpace
            )
        else { return }
        credentialDetailRequest = request
    }

    func delete(_ descriptor: CredentialDescriptor) {
        pendingDeletion = nil
        credentials.delete(
            descriptor,
            reloading: selectedSpaceID,
            accessController: spaceAccess
        )
    }

    func prepareExport() {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return }
        Task { @MainActor in
            isExporting = await credentials.prepareExport(
                in: selectedSpaceID,
                accessController: spaceAccess
            ) {
                self.selectedSpaceID == selectedSpaceID
                    && self.canRevealSelectedSpaceData
            }
        }
    }

    func finishExport(didFail: Bool) {
        if didFail {
            credentials.reportExportFailure()
        }
        credentials.exportDocument = nil
    }

    func clearSensitivePresentation() {
        pendingDeletion = nil
        credentialDetailRequest = nil
        confirmsPlaintextExport = false
        isExporting = false
        credentials.clearSensitiveData()
    }
}
