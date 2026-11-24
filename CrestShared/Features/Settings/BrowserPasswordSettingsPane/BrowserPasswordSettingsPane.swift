import SwiftUI
import UniformTypeIdentifiers

// MARK: - Types

struct BrowserSettingsSpaceDataRequest: Equatable {
    let assignment: BrowserSpaceRuntimeAssignment?
    let canRevealSpaceData: Bool
}

/// The order Settings lists a Space's saved passwords in.
struct BrowserPasswordSortOrder: Hashable, Identifiable, Sendable {
    static let name = BrowserPasswordSortOrder(id: "name", title: "Name") { $0.precedesInSettings($1) }
    static let site = BrowserPasswordSortOrder(id: "site", title: "Website") {
        $0.origin.host.localizedStandardCompare($1.origin.host) == .orderedAscending
    }
    static let lastUsed = BrowserPasswordSortOrder(id: "lastUsed", title: "Last Used") {
        ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast)
    }
    static let changed = BrowserPasswordSortOrder(id: "changed", title: "Last Changed") {
        ($0.passwordChangedAt ?? $0.updatedAt) > ($1.passwordChangedAt ?? $1.updatedAt)
    }
    static let all = [name, site, lastUsed, changed]

    let id: String
    let title: LocalizedStringResource
    let precedes: @Sendable (CredentialDescriptor, CredentialDescriptor) -> Bool

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Shared Space password preferences and manager, configured by each platform's layout.
/// `header` heads the pane where Autofill shows it, with its Space picker and
/// the choice of what to show.
struct BrowserPasswordSettingsPane<Header: View>: View {
    private static var disabledDescription: String { "Saved passwords stay here until you delete them." }

    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let layout: BrowserPasswordSettingsLayout
    /// Accepts the Settings window's search query.
    @Binding var searchText: String
    /// Opens the password manager when the platform presents it separately.
    var manage: (() -> Void)?
    /// The one Space whose passwords the pane shows, or nil to pick one.
    let fixedSpaceID: UUID?
    /// What heads the pane, where Autofill puts its own picker there.
    let header: Header
    /// Opens the import of passwords from another browser on this device,
    /// where the shell offers it.
    var importFromAnotherBrowser: (() -> Void)? = nil

    @State private var credentials: BrowserCredentialSpaceStore
    @State private var pickedSpaceID: UUID?
    private var selectedSpaceID: UUID? { fixedSpaceID ?? pickedSpaceID }
    private var selectedSpaceBinding: Binding<UUID?> {
        Binding(get: { selectedSpaceID }, set: { if fixedSpaceID == nil { pickedSpaceID = $0 } })
    }
    @State private var credentialPendingDeletion: CredentialDescriptor?
    @State private var credentialDetailRequest: BrowserCredentialDetailRequest?
    @State private var confirmsPlaintextExport = false
    @State private var isExporting = false
    @State private var isChoosingImportFile = false
    @State private var isSelectingCredentials = false
    @State private var selectedCredentialIDs: Set<UUID> = []
    @State private var confirmsSelectionDeletion = false
    @State private var confirmsUnreadableRemoval = false
    @State private var sortOrder = BrowserPasswordSortOrder.name
    /// The concern the list shows only the logins with, or nil for all.
    @State private var concernFilter: PasswordConcern?
    /// Whether the list shows only the logins that make one-time codes.
    @State private var showsOnlyCodes = false
    @State private var exportsSelection = false

    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        layout: BrowserPasswordSettingsLayout,
        searchText: Binding<String> = .constant(""),
        manage: (() -> Void)? = nil,
        fixedSpaceID: UUID? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.browser = browser
        self.spaceAccess = spaceAccess
        self.layout = layout
        _searchText = searchText
        self.manage = manage
        self.fixedSpaceID = fixedSpaceID
        self.header = header()
        _credentials = State(
            initialValue: BrowserCredentialSpaceStore(browser: browser)
        )
    }

    var body: some View {
        BrowserSettingsPane(.passwords) {
            settingsSections
            BrowserSpaceGroupSharingNote(browser: browser, spaceID: selectedSpaceID)
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
                "The CSV file will contain readable usernames, passwords and notes from only the selected Space. Anyone with the file can read them. Crest will authenticate you before opening the \(layout.exportDestinationName)."
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
        .alert(
            "Remove Passwords Crest Can’t Read?",
            isPresented: $confirmsUnreadableRemoval
        ) {
            Button("Remove", role: .destructive) {
                guard let selectedSpaceID else { return }
                credentials.deleteUnreadable(in: selectedSpaceID, accessController: spaceAccess)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Crest can’t show or fill them. This cannot be undone.")
        }
        .sheet(item: $credentialDetailRequest) { request in
            BrowserCredentialDetailView(
                browser: browser,
                spaceAccess: spaceAccess,
                request: request,
                changePasswordOnWebsite: { origin in
                    openChangePasswordPage(for: origin, in: request.spaceAssignment.spaceID)
                },
                delete: {
                    credentialDetailRequest = nil
                    credentials.delete(request.descriptor, reloading: selectedSpaceID, accessController: spaceAccess)
                }
            )
            .id(request.id)
            .onDisappear {
                Task { await credentials.load(in: selectedSpaceID, accessController: spaceAccess) }
            }
        }
        .sheet(item: $credentials.importReview) { review in
            BrowserCredentialImportReviewView(
                initialReviewID: review.id,
                credentials: credentials,
                browser: browser,
                spaceAccess: spaceAccess
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
        header
        if fixedSpaceID == nil {
            Section {
                CrestSpaceMenuPicker(
                    "Space",
                    selection: selectedSpaceBinding,
                    spaces: CrestSpaceIdentity.list(browser.spaceModels)
                )
            }
        }

        if let space {
            if canRevealSelectedSpaceData {
                Section {
                    Toggle(
                        "Use Crest Passwords",
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
                            Button("Manage Saved Passwords…") {
                                manage?()
                            }
                        }

                    }
                    .disabled(!space.settings.credentialPreferences.isEnabled)
                } header: {
                    Text("Crest Passwords")
                } footer: {
                    if !space.settings.credentialPreferences.isEnabled {
                        Text(Self.disabledDescription).crestFormFootnote()
                    } else if layout.showsCredentialPreferences {
                        CrestFormFootnote("iCloud Keychain and Passwords choices apply to this device only.")
                    }
                }

                if layout.showsSavedPasswords {
                    Section {
                        listBar(space: space)
                        healthChips
                        if isSelectingCredentials {
                            selectionActions
                        }
                        savedPasswords
                        if credentials.unreadableCount > 0 {
                            unreadablePasswords
                        }
                    } header: {
                        Text("Saved passwords")
                    } footer: {
                        if !credentials.descriptors.isEmpty {
                            Text(passwordCountLabel).crestFormFootnote()
                        }
                    }

                    neverSavedSites(in: space)
                }

                if fixedSpaceID == nil || Header.self != EmptyView.self {
                    Section("System passkeys") {
                        BrowserPasskeyAccessView()
                    }
                }

                if let errorMessage = credentials.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(CrestColor.danger)
                    }
                }
            } else {
                BrowserSettingsPrivateSpaceAccessSection(
                    space: space,
                    accessController: spaceAccess,
                    detail: "Unlock this Space to see its passwords."
                )
            }
        }
    }

    /// The list's search field, its order, and everything else it does,
    /// in the ⋯ menu.
    private func listBar(space: SpaceModel) -> some View {
        HStack(spacing: CrestSpacing.small) {
            CrestSearchField("Search saved passwords", text: $searchText)
                .accessibilityIdentifier("saved-password-search")
            Menu {
                Picker("Sort By", selection: $sortOrder) {
                    ForEach(BrowserPasswordSortOrder.all) { order in
                        Text(order.title).tag(order)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort By")
            .accessibilityLabel("Sort By")
            Menu {
                Group {
                    if layout.supportsCredentialFileImport {
                        Button("Import Passwords…", systemImage: "square.and.arrow.down") {
                            isChoosingImportFile = true
                        }
                        .disabled(
                            !space.settings.credentialPreferences.isEnabled
                                || credentials.isPreparingImport
                                || credentials.isCommittingImport
                        )
                        .accessibilityIdentifier("import-space-passwords")
                    }
                    if layout.showsExportAction {
                        Button("Export Passwords…", systemImage: "square.and.arrow.up") {
                            exportsSelection = false
                            confirmsPlaintextExport = true
                        }
                        .disabled(credentials.descriptors.isEmpty || credentials.isPreparingExport)
                        .accessibilityIdentifier("export-space-passwords")
                    }
                    if let importFromAnotherBrowser {
                        Button(
                            "Import from Another Browser…", systemImage: "arrow.down.app",
                            action: importFromAnotherBrowser)
                    }
                    Divider()
                    Button(
                        isSelectingCredentials ? "Done Selecting" : "Select",
                        systemImage: "checkmark.circle"
                    ) {
                        isSelectingCredentials.toggle()
                        if !isSelectingCredentials { selectedCredentialIDs.removeAll() }
                    }
                    .disabled(credentials.descriptors.isEmpty || credentials.isDeletingSelection)
                }
                .crestMenuActionLabelStyle()
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .accessibilityLabel("More")
            .accessibilityIdentifier("saved-password-actions")
        }
    }

    /// How many logins have each concern, each a filter for the list.
    @ViewBuilder
    private var healthChips: some View {
        let counts = credentials.concernCounts
        let codes = credentials.extras.values.count(where: \.hasCode)
        if !counts.isEmpty || codes > 0 {
            HStack(spacing: CrestSpacing.small) {
                if codes > 0 {
                    Button {
                        showsOnlyCodes.toggle()
                    } label: {
                        Label("\(codes) with codes", systemImage: "clock.badge.checkmark")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, CrestSpacing.small)
                            .padding(.vertical, CrestSpacing.extraSmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(showsOnlyCodes ? CrestBrandTheme.accentText : .secondary)
                    .crestHoverSurface(
                        isSelected: showsOnlyCodes, cornerRadius: CrestRadius.compact, showsRestingSurface: true
                    )
                    .accessibilityAddTraits(showsOnlyCodes ? .isSelected : [])
                    .accessibilityIdentifier("password-filter-codes")
                }
                ForEach(counts, id: \.concern) { entry in
                    Button {
                        concernFilter = concernFilter == entry.concern ? nil : entry.concern
                    } label: {
                        Label {
                            Text("\(entry.count) \(Text(entry.concern.title))")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, CrestSpacing.small)
                        .padding(.vertical, CrestSpacing.extraSmall)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(concernFilter == entry.concern ? CrestBrandTheme.accentText : CrestColor.warning)
                    .crestHoverSurface(
                        isSelected: concernFilter == entry.concern, cornerRadius: CrestRadius.compact,
                        showsRestingSurface: true
                    )
                    .accessibilityAddTraits(concernFilter == entry.concern ? .isSelected : [])
                    .accessibilityIdentifier("password-health-\(entry.concern.name)")
                }
                Spacer()
            }
        }
    }

    /// What the person can do with the passwords they selected.
    private var selectionActions: some View {
        HStack {
            Button("Select All") {
                selectedCredentialIDs = Set(filteredDescriptors.map(\.id))
            }
            .disabled(filteredDescriptors.isEmpty)
            Spacer()
            Menu("Move to Space") {
                Group {
                    ForEach(otherSpaces) { space in
                        Button {
                            moveSelectedCredentials(to: space.id)
                        } label: {
                            BrowserSpaceIdentityLabel(identity: space.identity)
                        }
                    }
                }
                .crestMenuActionLabelStyle()
            }
            .fixedSize()
            .disabled(selectedCredentialIDs.isEmpty || otherSpaces.isEmpty || credentials.isDeletingSelection)
            if layout.showsExportAction {
                Button("Export…") {
                    exportsSelection = true
                    confirmsPlaintextExport = true
                }
                .disabled(selectedCredentialIDs.isEmpty || credentials.isPreparingExport)
            }
            Button("Delete", role: .destructive) {
                confirmsSelectionDeletion = true
            }
            .disabled(selectedCredentialIDs.isEmpty || credentials.isDeletingSelection)
        }
    }

    /// The sites the Space never offers to save a password for, each with a
    /// way to let it offer again.
    @ViewBuilder
    private func neverSavedSites(in space: SpaceModel) -> some View {
        let sites = space.settings.credentialPreferences.neverSavedSites
        if !sites.isEmpty {
            Section("Never saved") {
                ForEach(sites, id: \.self) { site in
                    HStack {
                        Text(site.description)
                        Spacer()
                        Button("Remove") {
                            browser.allowSavingCredentials(for: site, in: space.id)
                        }
                        .accessibilityIdentifier("allow-saving-\(site.host)")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func credentialPreferences(in space: SpaceModel) -> some View {
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

        if browser.systemPasswordWriteThroughAvailability == .available {
            Toggle(
                "Offer a copy to Passwords",
                isOn: browser.credentialPreferenceBinding(
                    \.alsoOffersSaveToSystemPasswords,
                    in: space
                )
            )
        }
    }

    @ViewBuilder
    private var savedPasswords: some View {
        let descriptors = filteredDescriptors

        if credentials.isLoading {
            ProgressView("Reading this Space’s Keychain…")
                .frame(maxWidth: .infinity)
        } else if descriptors.isEmpty {
            // Passwords that can't be read have their own row, so the Space
            // isn't called empty above it.
            if !searchText.isEmpty || credentials.unreadableCount == 0 {
                Text(searchText.isEmpty ? "No saved passwords" : "No matches")
                    .foregroundStyle(.secondary)
            }
        } else {
            CrestFormRows(descriptors) { descriptor in
                BrowserPasswordDescriptorRow(
                    descriptor: descriptor,
                    space: space?.identity,
                    extras: credentials.extras[descriptor.id],
                    concerns: credentials.health[descriptor.id]?.concerns ?? [],
                    isDeleting: credentials.isDeleting(descriptor),
                    isSelectionActive: isSelectingCredentials,
                    isSelected: selectedCredentialIDs.contains(descriptor.id),
                    showDetails: {
                        guard let space,
                            let request = BrowserCredentialDetailRequest(
                                descriptor: descriptor,
                                space: space,
                                extras: credentials.extras[descriptor.id],
                                concerns: credentials.health[descriptor.id]?.concerns ?? []
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

    private var unreadablePasswords: some View {
        HStack {
            Label(unreadablePasswordsLabel, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Remove…", role: .destructive) {
                confirmsUnreadableRemoval = true
            }
            .accessibilityIdentifier("remove-unreadable-passwords")
        }
    }

    // MARK: - Derived state

    private var space: SpaceModel? {
        guard let selectedSpaceID else { return nil }
        return browser.spaceModel(selectedSpaceID)
    }

    private var filteredDescriptors: [CredentialDescriptor] {
        credentials.descriptors(matching: searchText)
            .filter { descriptor in
                concernFilter.map { credentials.health[descriptor.id]?.concerns.contains($0) == true } ?? true
            }
            .filter { !showsOnlyCodes || credentials.extras[$0.id]?.hasCode == true }
            .sorted(by: sortOrder.precedes)
    }

    /// The Spaces a selection can move to: every other one this window may open.
    private var otherSpaces: [SpaceModel] {
        browser.spaceModels.filter { $0.id != selectedSpaceID && !spaceAccess.isLocked($0) }
    }

    private var canRevealSelectedSpaceData: Bool {
        guard let space else { return false }
        return !spaceAccess.isLocked(space)
    }

    private var credentialLoadRequest: BrowserSettingsSpaceDataRequest {
        BrowserSettingsSpaceDataRequest(
            assignment: space.map(BrowserSpaceRuntimeAssignment.init(space:)),
            canRevealSpaceData: canRevealSelectedSpaceData
        )
    }

    private var passwordCountLabel: String {
        String(localized: "\(credentials.descriptors.count) passwords")
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

    private var selectionDeletionMessage: String {
        let spaceName = space?.settings.name ?? String(localized: "this Space")
        return String(
            localized:
                "Delete \(selectedCredentialIDs.count) selected passwords from \(spaceName)? Crest will authenticate you and apply the deletion as one Keychain change. This cannot be undone."
        )
    }

    private var unreadablePasswordsLabel: String {
        String(localized: "\(credentials.unreadableCount) saved passwords can’t be read")
    }

    private var selectionDeletionButtonLabel: String {
        String(localized: "Delete \(selectedCredentialIDs.count) Passwords")
    }

    private func prepareExport() {
        guard let selectedSpaceID, canRevealSelectedSpaceData else { return }
        let only = exportsSelection ? selectedCredentialIDs : nil
        Task { @MainActor in
            isExporting = await credentials.prepareExport(
                in: selectedSpaceID,
                only: only,
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
        confirmsUnreadableRemoval = false
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

    /// Opens the site's own page for changing a password, the address sites
    /// agree on for it, in a new tab of the Space.
    private func openChangePasswordPage(for origin: CredentialOrigin, in spaceID: UUID) {
        guard let url = URL(string: "\(origin.description)/.well-known/change-password") else { return }
        credentialDetailRequest = nil
        _ = browser.openNewTab(url: url, in: spaceID)
    }

    private func moveSelectedCredentials(to destination: UUID) {
        guard let selectedSpaceID else { return }
        let ids = selectedCredentialIDs
        Task { @MainActor in
            if await credentials.move(ids, from: selectedSpaceID, to: destination, accessController: spaceAccess) {
                selectedCredentialIDs.removeAll()
                isSelectingCredentials = false
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

extension BrowserPasswordSettingsPane where Header == EmptyView {
    init(
        browser: BrowserStore,
        spaceAccess: BrowserSpaceAccessController,
        layout: BrowserPasswordSettingsLayout,
        searchText: Binding<String> = .constant(""),
        manage: (() -> Void)? = nil,
        fixedSpaceID: UUID? = nil
    ) {
        self.init(
            browser: browser, spaceAccess: spaceAccess, layout: layout, searchText: searchText, manage: manage,
            fixedSpaceID: fixedSpaceID
        ) { EmptyView() }
    }
}

extension BrowserPasswordSettingsPane {
    /// The pane with Import from Another Browser in its ⋯ menu, opening `action`.
    func importingFromAnotherBrowser(_ action: (() -> Void)?) -> Self {
        var pane = self
        pane.importFromAnotherBrowser = action
        return pane
    }
}
