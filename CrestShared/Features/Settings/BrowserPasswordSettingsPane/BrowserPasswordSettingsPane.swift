import SwiftUI
import UniformTypeIdentifiers

/// Shared Space password preferences and manager, configured by each platform's layout.
struct BrowserPasswordSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let layout: BrowserPasswordSettingsLayout
    /// Accepts the Settings window's search query.
    @Binding var searchText: String
    /// Opens the password manager when the platform presents it separately.
    var manage: (() -> Void)?

    @State private var credentials: BrowserCredentialSpaceStore
    @Environment(\.browserSettingsSelections) private var selections
    @State private var localSelectedSpaceID: SpaceID?
    private var selectedSpaceID: SpaceID? {
        get { if let selections { selections.passwordSpaceID } else { localSelectedSpaceID } }
        nonmutating set {
            if let selections { selections.passwordSpaceID = newValue } else { localSelectedSpaceID = newValue }
        }
    }
    private var selectedSpaceBinding: Binding<SpaceID?> {
        Binding(get: { selectedSpaceID }, set: { selectedSpaceID = $0 })
    }
    @State private var credentialPendingDeletion: CredentialDescriptor?
    @State private var credentialDetailRequest: BrowserCredentialDetailRequest?
    @State private var confirmsPlaintextExport = false
    @State private var isExporting = false
    @State private var isChoosingImportFile = false
    @State private var isSelectingCredentials = false
    @State private var selectedCredentialIDs: Set<CredentialID> = []
    @State private var confirmsSelectionDeletion = false

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        layout: BrowserPasswordSettingsLayout,
        searchText: Binding<String> = .constant(""),
        manage: (() -> Void)? = nil
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.layout = layout
        _searchText = searchText
        self.manage = manage
        _credentials = State(
            initialValue: BrowserCredentialSpaceStore(browser: browser)
        )
    }

    var body: some View {
        BrowserSettingsPane(.passwords) {
            settingsSections
        }
        .crestRepairsSpaceSelection(selectedSpaceBinding, in: browser)
        .task(id: credentialLoadRequest) {
            await credentials.load(
                in: selectedSpaceID,
                accessController: spaceAccess
            )
        }
        .onChange(of: credentialLoadRequest, initial: true) { previous, request in
            if previous.assignment != request.assignment
                || !request.canRevealSpaceData
            {
                clearSensitivePresentation()
            }
        }
        .alert(
            "Delete Password?",
            isPresented: deletionAlertIsPresented,
            presenting: credentialPendingDeletion
        ) { descriptor in
            Button("Delete", role: .destructive) {
                credentialPendingDeletion = nil
                credentials.delete(
                    descriptor,
                    reloading: selectedSpaceID,
                    accessController: spaceAccess
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: { descriptor in
            Text(credentials.deletionMessage(for: descriptor, in: space))
        }
        .alert(
            "Export Passwords as Plaintext?",
            isPresented: $confirmsPlaintextExport
        ) {
            Button("Export…") { prepareExport() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "The CSV file will contain readable usernames and passwords from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the \(layout.exportDestinationName)."
            )
        }
        .confirmationDialog(
            "Delete Selected Passwords?",
            isPresented: $confirmsSelectionDeletion,
            titleVisibility: .visible
        ) {
            Button(selectionDeletionButtonLabel, role: .destructive) {
                deleteSelectedCredentials()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(selectionDeletionMessage)
        }
        .sheet(item: $credentialDetailRequest) { request in
            BrowserCredentialDetailView(
                browser: browser,
                spaceAccess: spaceAccess,
                request: request
            )
            .id(request.id)
        }
        .sheet(item: $credentials.importPlan) { plan in
            BrowserCredentialImportReviewView(
                initialPlanID: plan.id,
                credentials: credentials,
                browser: browser,
                spaceAccess: spaceAccess
            )
        }
        .alert(
            "Password Import Finished",
            isPresented: importSummaryIsPresented,
            presenting: credentials.importSummary
        ) { _ in
            Button("OK") { credentials.importSummary = nil }
        } message: { summary in
            Text(
                "Accepted \(summary.acceptedCount), skipped \(summary.skippedCount), reviewed \(summary.warningCount) warnings, and rejected \(summary.rejectedCount) from the selected file."
            )
        }
        .fileImporter(
            isPresented: $isChoosingImportFile,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            openImportResult(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: credentials.exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: credentials.exportFilename
        ) { result in
            if case .failure = result {
                credentials.reportExportFailure()
            }
            credentials.exportDocument = nil
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var settingsSections: some View {
        Section("System passkeys", systemImage: "person.badge.key") {
            BrowserPasskeyAccessView()
        }

        Section("Space", systemImage: "square.grid.2x2") {
            CrestSpaceMenuPicker(
                "Passwords for",
                selection: selectedSpaceBinding,
                spaces: CrestSpaceIdentity.list(browser.session.spaces)
            )
        }

        if let space {
            if canRevealSelectedSpaceData {
                Section("Crest Passwords", systemImage: "key") {
                    Toggle(
                        "Use Crest Passwords in this Space",
                        isOn: browser.credentialPreferenceBinding(
                            \.isEnabled,
                            in: space
                        )
                    )
                    .accessibilityIdentifier(
                        "space-crest-passwords-enabled"
                    )

                    Group {
                        if layout.showsCredentialPreferences {
                            credentialPreferences(in: space)
                        }

                        if layout.showsManageAction {
                            Button(
                                "Manage Saved Passwords…",
                                systemImage: "key.fill"
                            ) {
                                manage?()
                            }
                            .buttonStyle(.crestTertiary)
                        }

                        if layout.showsExportAction {
                            Button(
                                "Export Passwords…",
                                systemImage: "square.and.arrow.up"
                            ) {
                                confirmsPlaintextExport = true
                            }
                            .buttonStyle(.crestTertiary)
                            .disabled(
                                credentials.descriptors.isEmpty
                                    || credentials.isPreparingExport
                            )
                            .accessibilityIdentifier(
                                "export-space-passwords"
                            )
                        }
                    }
                    .disabled(!space.credentialPreferences.isEnabled)

                    if !space.credentialPreferences.isEnabled {
                        Text(BrowserCredentialSettingsPolicy.disabledDescription)
                            .crestFormFootnote()
                    }
                }

                if layout.showsSavedPasswords {
                    Section("Saved passwords", systemImage: "key.horizontal") {
                        if !credentials.descriptors.isEmpty || !searchText.isEmpty {
                            BrowserCredentialSearchField(
                                title: "Search saved passwords",
                                text: $searchText,
                                accessibilityIdentifier: "saved-password-search"
                            )
                        }
                        passwordManagerActions
                        savedPasswords
                        Text(passwordCountLabel).crestFormFootnote()
                    }
                }

                if let errorMessage = credentials.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .crestFormFootnote()
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if layout.showsSavedPasswords {
                        CrestFormFootnote(
                            "Crest shows descriptor metadata only. Password values stay in the active Space’s Data Protection Keychain and never enter session or CloudKit data."
                        )
                    } else {
                        CrestFormFootnote(
                            "Crest Passwords stay in this Space. They never enter another Space’s suggestions or records."
                        )
                    }
                }
            } else {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: space,
                    accessController: spaceAccess,
                    detail:
                        "Unlock this Space before viewing account and site metadata or changing its password settings."
                )
            }
        }
    }

    @ViewBuilder
    private var passwordManagerActions: some View {
        if layout.supportsCredentialFileImport, let space {
            ViewThatFits {
                HStack {
                    importButton(space: space)
                    Spacer()
                    selectionButton
                }
                VStack(alignment: .leading) {
                    importButton(space: space)
                    selectionButton
                }
            }

            if isSelectingCredentials {
                HStack {
                    Button("Select All") {
                        selectedCredentialIDs = Set(filteredDescriptors.map(\.id))
                    }
                    .disabled(filteredDescriptors.isEmpty)

                    Button("Delete Selected", role: .destructive) {
                        confirmsSelectionDeletion = true
                    }
                    .disabled(
                        selectedCredentialIDs.isEmpty
                            || credentials.isDeletingSelection
                    )
                }
            }
        }
    }

    private func importButton(space: BrowserSpace) -> some View {
        Button(
            "Import into \(space.name)…",
            systemImage: "square.and.arrow.down"
        ) {
            isChoosingImportFile = true
        }
        .buttonStyle(.crestTertiary)
        .disabled(
            !space.credentialPreferences.isEnabled
                || credentials.isPreparingImport
                || credentials.isCommittingImport
        )
        .accessibilityIdentifier("import-space-passwords")
    }

    private var selectionButton: some View {
        Button(
            isSelectingCredentials ? "Done Selecting" : "Select Passwords",
            systemImage: isSelectingCredentials ? "checkmark" : "checkmark.circle"
        ) {
            isSelectingCredentials.toggle()
            if !isSelectingCredentials { selectedCredentialIDs.removeAll() }
        }
        .buttonStyle(.crestTertiary)
        .disabled(credentials.descriptors.isEmpty || credentials.isDeletingSelection)
    }

    @ViewBuilder
    private func credentialPreferences(in space: BrowserSpace) -> some View {
        Toggle(
            "Sync with iCloud Keychain",
            isOn: credentials.synchronizationBinding(
                in: space,
                accessController: spaceAccess
            )
        )
        .disabled(credentials.isChangingSynchronization)

        if credentials.isChangingSynchronization {
            ProgressView("Updating existing credentials…")
        }

        if BrowserSystemPasswordWriteThroughSystem.launchAvailability
            == .available
        {
            Toggle(
                "Offer a copy to Passwords",
                isOn: browser.credentialPreferenceBinding(
                    \.alsoOffersSaveToSystemPasswords,
                    in: space
                )
            )

            Text(
                BrowserSystemPasswordWriteThroughSystem.launchAvailability
                    .detail
            )
            .crestFormFootnote()
        }
    }

    @ViewBuilder
    private var savedPasswords: some View {
        let descriptors = filteredDescriptors

        if credentials.isLoading {
            ProgressView("Reading this Space’s Keychain…")
                .frame(maxWidth: .infinity)
        } else if descriptors.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No Saved Passwords" : "No Matching Passwords",
                systemImage: searchText.isEmpty ? "key.slash" : "magnifyingglass",
                description: Text(
                    space?.credentialPreferences.isEnabled == false
                        ? BrowserCredentialSettingsPolicy.disabledDescription
                        : credentials.emptyDescription(
                            isSearching: !searchText.isEmpty
                        )
                )
            )
            .frame(maxWidth: .infinity)
        } else {
            ForEach(descriptors) { descriptor in
                BrowserPasswordDescriptorRow(
                    descriptor: descriptor,
                    space: space,
                    isDeleting: credentials.isDeleting(descriptor),
                    isSelectionActive: isSelectingCredentials,
                    isSelected: selectedCredentialIDs.contains(descriptor.id),
                    showDetails: {
                        guard let space,
                            let request = BrowserCredentialDetailRequest(
                                descriptor: descriptor,
                                space: space
                            )
                        else { return }
                        credentialDetailRequest = request
                    },
                    requestDeletion: { credentialPendingDeletion = descriptor },
                    toggleSelection: {
                        if !selectedCredentialIDs.insert(descriptor.id).inserted {
                            selectedCredentialIDs.remove(descriptor.id)
                        }
                    }
                )
            }
        }
    }

    // MARK: - Derived state

    private var space: BrowserSpace? {
        guard let selectedSpaceID else { return nil }
        return browser.session.space(id: selectedSpaceID)
    }

    private var filteredDescriptors: [CredentialDescriptor] {
        credentials.descriptors(matching: searchText)
    }

    private var canRevealSelectedSpaceData: Bool {
        BrowserSettingsPrivacyPolicy.canRevealSpaceData(
            in: space,
            accessController: spaceAccess
        )
    }

    private var credentialLoadRequest: BrowserSettingsSpaceDataRequest {
        BrowserSettingsSpaceDataRequest(
            assignment: space.map(BrowserSpaceRuntimeAssignment.init(space:)),
            canRevealSpaceData: canRevealSelectedSpaceData
        )
    }

    private var passwordCountLabel: String {
        let count = credentials.descriptors.count
        return count == 1 ? "1 password" : "\(count) passwords"
    }

    private var deletionAlertIsPresented: Binding<Bool> {
        Binding {
            credentialPendingDeletion != nil
        } set: { isPresented in
            if !isPresented {
                credentialPendingDeletion = nil
            }
        }
    }

    private var importSummaryIsPresented: Binding<Bool> {
        Binding {
            credentials.importSummary != nil
        } set: { isPresented in
            if !isPresented { credentials.importSummary = nil }
        }
    }

    private var selectionDeletionMessage: String {
        let spaceName = space?.name ?? "this Space"
        let count = selectedCredentialIDs.count
        let passwordLabel = count == 1 ? "password" : "passwords"
        return
            "Delete \(count) selected \(passwordLabel) from \(spaceName)? Crest will authenticate you and apply the deletion as one Keychain change. This cannot be undone."
    }

    private var selectionDeletionButtonLabel: String {
        let count = selectedCredentialIDs.count
        return count == 1
            ? String(localized: "Delete 1 Password")
            : String(localized: "Delete \(count) Passwords")
    }

    private func prepareExport() {
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

    private func clearSensitivePresentation() {
        credentialPendingDeletion = nil
        credentialDetailRequest = nil
        confirmsPlaintextExport = false
        isExporting = false
        isChoosingImportFile = false
        isSelectingCredentials = false
        selectedCredentialIDs.removeAll()
        confirmsSelectionDeletion = false
        credentials.clearSensitiveData()
    }

    private func openImportResult(_ result: Result<[URL], any Error>) {
        guard case .success(let urls) = result,
            let url = urls.first,
            let selectedSpaceID
        else {
            if case .failure = result {
                credentials.errorMessage = "Crest couldn’t open that password file."
            }
            return
        }
        Task { @MainActor in
            await credentials.prepareImport(
                from: url,
                in: selectedSpaceID,
                accessController: spaceAccess
            ) {
                self.selectedSpaceID == selectedSpaceID
                    && self.canRevealSelectedSpaceData
            }
        }
    }

    private func deleteSelectedCredentials() {
        guard let selectedSpaceID else { return }
        let ids = selectedCredentialIDs
        Task { @MainActor in
            if await credentials.deleteSelection(
                ids,
                in: selectedSpaceID,
                accessController: spaceAccess,
                isStillSelected: {
                    self.selectedSpaceID == selectedSpaceID
                        && self.canRevealSelectedSpaceData
                }
            ) {
                selectedCredentialIDs.removeAll()
                isSelectingCredentials = false
            }
        }
    }
}
