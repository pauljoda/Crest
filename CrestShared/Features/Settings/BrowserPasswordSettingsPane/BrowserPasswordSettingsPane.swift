import SwiftUI
import UniformTypeIdentifiers

/// Crest Passwords, per Space.
///
/// The two shells split this pane along different lines: the desktop put the whole
/// manager on the page, while touch put the preferences on the page and the manager
/// behind a sheet. Both drew the same Space picker, the same passkey status, the same
/// descriptor rows, and the same four failure sentences. This is that pane once; what
/// each shell shows of it is a ``BrowserPasswordSettingsLayout``, because the split is a shipped shape
/// rather than a styling choice — and because it is the kind of thing a test can pin.
struct BrowserPasswordSettingsPane: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let layout: BrowserPasswordSettingsLayout
    /// The desktop searches this pane from the Settings window's own search field,
    /// so the query arrives from outside the pane.
    @Binding var searchText: String
    /// What a shell that keeps the manager elsewhere does when asked for it.
    var manage: (() -> Void)?

    @State private var credentials: BrowserCredentialSpaceStore
    @State private var selectedSpaceID: SpaceID?
    @State private var credentialPendingDeletion: CredentialDescriptor?
    @State private var credentialDetailRequest: BrowserCredentialDetailRequest?
    @State private var confirmsPlaintextExport = false
    @State private var isExporting = false

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
            Section("System passkeys") {
                BrowserPasskeyAccessView()
            }

            Section("Space") {
                CrestSpaceMenuPicker(
                    "Passwords for",
                    selection: $selectedSpaceID,
                    spaces: CrestSpaceIdentity.list(browser.session.spaces)
                )
            }

            if let space {
                if canRevealSelectedSpaceData {
                    Section("Crest Passwords") {
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
                        Section("Saved passwords") {
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
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
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
                "The CSV file will contain readable usernames and passwords from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the save panel."
            )
        }
        .sheet(item: $credentialDetailRequest) { request in
            BrowserCredentialDetailView(
                browser: browser,
                spaceAccess: spaceAccess,
                request: request
            )
            .id(request.id)
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
                    showDetails: {
                        guard let space,
                            let request = BrowserCredentialDetailRequest(
                                descriptor: descriptor,
                                space: space
                            )
                        else { return }
                        credentialDetailRequest = request
                    },
                    requestDeletion: { credentialPendingDeletion = descriptor }
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
        credentials.clearSensitiveData()
    }
}

#Preview("Password Settings Pane") {
    BrowserPasswordSettingsPane(
        browser: BrowserStore.preview(),
        spaceAccess: BrowserSpaceAccessController(),
        layout: .macOSPage
    )
}
