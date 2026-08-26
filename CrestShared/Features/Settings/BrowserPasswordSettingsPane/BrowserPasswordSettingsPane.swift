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

private struct BrowserCredentialImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let initialPlanID: UUID
    let credentials: BrowserCredentialSpaceStore
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    @State private var searchText = ""
    @State private var revealedGroupIDs: Set<BrowserCredentialImportGroupID> = []

    var body: some View {
        NavigationStack {
            Group {
                if let plan = credentials.importPlan,
                    plan.id == initialPlanID,
                    let space = browser.space(matching: plan.destination)
                {
                    VStack(spacing: 0) {
                        ScrollView {
                            LazyVStack(
                                alignment: .leading,
                                spacing: CrestSpacing.extraExtraLarge
                            ) {
                                BrowserCredentialImportDestinationCard(
                                    space: space,
                                    format: plan.format
                                )
                                BrowserCredentialImportSummaryView(plan: plan)

                                if !plan.groups.isEmpty {
                                    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                                        BrowserCredentialImportReviewSectionHeader(
                                            title: "Accounts",
                                            detail:
                                                "Review every valid account. Choose which password to keep, or skip any account."
                                        )

                                        BrowserCredentialSearchField(
                                            title: "Search imported passwords",
                                            text: $searchText,
                                            accessibilityIdentifier:
                                                "imported-password-search"
                                        )
                                    }

                                    let matchingGroups = plan.groups(matching: searchText)
                                    if matchingGroups.isEmpty {
                                        ContentUnavailableView.search(text: searchText)
                                            .frame(maxWidth: .infinity)
                                    } else {
                                        ForEach(matchingGroups) { group in
                                            BrowserCredentialImportAccountRow(
                                                group: group,
                                                revealsPasswords:
                                                    revealedGroupIDs.contains(group.id),
                                                select: { selection in
                                                    credentials.selectImport(
                                                        selection,
                                                        for: group.id
                                                    )
                                                },
                                                togglePasswordVisibility: {
                                                    if !revealedGroupIDs.insert(group.id)
                                                        .inserted
                                                    {
                                                        revealedGroupIDs.remove(group.id)
                                                    }
                                                }
                                            )
                                        }
                                    }
                                }

                                if !plan.warnings.isEmpty {
                                    BrowserCredentialImportWarningRows(
                                        warnings: plan.warnings
                                    )
                                }

                                if !plan.rejections.isEmpty {
                                    BrowserCredentialImportRejectedRows(
                                        rejections: plan.rejections
                                    )
                                }

                                Label(
                                    "Passwords remain encrypted in this Space’s Keychain and never appear in logs, notifications, or diagnostics.",
                                    systemImage: "lock.shield.fill"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                            .padding(CrestSpacing.extraExtraLarge)
                        }

                        Divider()
                        importFooter(plan: plan, space: space)
                    }
                } else {
                    ContentUnavailableView(
                        "Import No Longer Available",
                        systemImage: "key.slash",
                        description: Text(
                            "The destination Space changed. Choose the file again."
                        )
                    )
                }
            }
            .navigationTitle("Review Password Import")
            .interactiveDismissDisabled(credentials.isCommittingImport)
        }
        .browserCredentialImportReviewSizing()
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { revealedGroupIDs.removeAll() }
        }
        .onDisappear { revealedGroupIDs.removeAll() }
    }

    private func importFooter(
        plan: BrowserCredentialImportPlan,
        space: BrowserSpace
    ) -> some View {
        HStack(spacing: CrestSpacing.medium) {
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("Ready for \(space.name)")
                    .font(.subheadline.weight(.semibold))
                Text(importSummary(plan))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: CrestSpacing.medium)

            if credentials.isCommittingImport {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Importing passwords")
            }

            Button("Cancel") {
                credentials.cancelImport()
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(credentials.isCommittingImport)

            Button(credentials.isCommittingImport ? "Importing…" : "Import") {
                commit()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(
                credentials.importPlan == nil
                    || credentials.isCommittingImport
            )
        }
        .padding(.horizontal, CrestSpacing.extraExtraLarge)
        .padding(.vertical, CrestSpacing.large)
        .background(.bar)
    }

    private func importSummary(_ plan: BrowserCredentialImportPlan) -> String {
        guard let summary = try? plan.resolvedInventory().summary else {
            return "Review the file before importing."
        }
        return
            "\(summary.acceptedCount) to import, \(summary.skippedCount) to keep or skip, \(warningLabel(summary.warningCount)), \(summary.rejectedCount) rejected."
    }

    private func warningLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "1 warning")
            : String(localized: "\(count) warnings")
    }

    private func commit() {
        Task { @MainActor in
            await credentials.commitImport(
                accessController: spaceAccess,
                isStillSelected: {
                    guard let plan = credentials.importPlan else { return false }
                    return browser.space(matching: plan.destination) != nil
                }
            )
            if credentials.importPlan == nil { dismiss() }
        }
    }
}

private struct BrowserCredentialImportDestinationCard: View {
    let space: BrowserSpace
    let format: BrowserCredentialCSVImportFormat

    var body: some View {
        HStack(alignment: .top, spacing: CrestSpacing.large) {
            Image(systemName: space.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text("Importing into")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(space.name)
                    .font(.title3.weight(.semibold))
                Text(
                    "Every accepted credential will be stored only in this Space’s Keychain inventory."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: CrestSpacing.small)

            Label(format.rawValue, systemImage: "doc.text")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, CrestSpacing.small)
                .padding(.vertical, 6)
                .background(Color.primary.opacity(0.055), in: Capsule())
        }
        .padding(CrestSpacing.large)
        .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.2))
        }
        .accessibilityElement(children: .combine)
    }
}

private struct BrowserCredentialImportSummaryView: View {
    let plan: BrowserCredentialImportPlan

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Review",
                detail: "Confirm what Crest will change before anything is saved."
            )

            ViewThatFits(in: .horizontal) {
                HStack(spacing: CrestSpacing.medium) {
                    metrics
                }
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: CrestSpacing.medium
                ) {
                    metrics
                }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        BrowserCredentialImportMetric(
            title: "Ready to import",
            value: plan.proposedImportCount,
            systemImage: "checkmark.circle.fill",
            color: .green
        )
        BrowserCredentialImportMetric(
            title: "Need review",
            value: plan.conflictCount,
            systemImage: "arrow.triangle.branch",
            color: .orange
        )
        BrowserCredentialImportMetric(
            title: "Warnings",
            value: plan.warnings.count,
            systemImage: "exclamationmark.shield.fill",
            color: .orange
        )
        BrowserCredentialImportMetric(
            title: "Rejected rows",
            value: plan.rejections.count,
            systemImage: "xmark.octagon.fill",
            color: .red
        )
    }
}

private struct BrowserCredentialImportWarningRows: View {
    let warnings: [BrowserCredentialCSVRowWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Warnings",
                detail:
                    "These credentials are valid and will be imported. Review the security limitation before continuing."
            )

            LazyVStack(spacing: 0) {
                ForEach(warnings, id: \.rowNumber) { warning in
                    HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
                        Text("Row \(warning.rowNumber)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(minWidth: 54, alignment: .leading)
                        Text(warning.reason.message)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, CrestSpacing.medium)

                    if warning.rowNumber != warnings.last?.rowNumber {
                        Divider()
                    }
                }
            }
            .padding(.horizontal, CrestSpacing.large)
            .background(Color.orange.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct BrowserCredentialImportMetric: View {
    let title: LocalizedStringKey
    let value: Int
    let systemImage: String
    let color: Color

    var body: some View {
        HStack(spacing: CrestSpacing.medium) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: CrestSpacing.extraExtraSmall) {
                Text("\(value)")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(CrestSpacing.medium)
        .frame(minWidth: 150, maxWidth: .infinity, minHeight: 72)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

private struct BrowserCredentialImportReviewSectionHeader: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct BrowserCredentialImportRejectedRows: View {
    let rejections: [BrowserCredentialCSVRowRejection]

    private var visibleRejections: [BrowserCredentialCSVRowRejection] {
        Array(rejections.prefix(100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserCredentialImportReviewSectionHeader(
                title: "Rejected rows",
                detail:
                    "These rows are excluded from the import. Correct the source file to import them later."
            )

            LazyVStack(spacing: 0) {
                ForEach(visibleRejections, id: \.rowNumber) { rejection in
                    HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
                        Text("Row \(rejection.rowNumber)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(minWidth: 54, alignment: .leading)
                        Text(rejection.reason.message)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, CrestSpacing.medium)

                    if rejection.rowNumber != visibleRejections.last?.rowNumber {
                        Divider()
                    }
                }

                if rejections.count > visibleRejections.count {
                    Divider()
                    Text(
                        "\(rejections.count - visibleRejections.count) additional rejected rows are included in the final count."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, CrestSpacing.medium)
                }
            }
            .padding(.horizontal, CrestSpacing.large)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct BrowserCredentialImportAccountRow: View {
    let group: BrowserCredentialImportGroup
    let revealsPasswords: Bool
    let select: (BrowserCredentialImportSelection) -> Void
    let togglePasswordVisibility: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text(group.origin.description)
                        .font(.headline)
                        .lineLimit(1)
                    Text(group.username.isEmpty ? "No username" : group.username)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: CrestSpacing.medium)
                HStack(spacing: CrestSpacing.small) {
                    if !group.origin.isSecure {
                        Label("HTTP", systemImage: "exclamationmark.shield.fill")
                            .foregroundStyle(.orange)
                    }
                    Label(status.title, systemImage: status.systemImage)
                        .foregroundStyle(status.color)
                }
                .font(.caption.weight(.medium))
            }

            if revealsPasswords {
                Divider()
                VStack(alignment: .leading, spacing: CrestSpacing.small) {
                    if let password = group.existingPasswordForReview {
                        BrowserCredentialImportPasswordValue(
                            label: "Current",
                            password: password
                        )
                    }
                    ForEach(
                        group.candidates.enumerated(),
                        id: \.element.rowNumber
                    ) { index, candidate in
                        BrowserCredentialImportPasswordValue(
                            label: importedPasswordLabel(
                                index: index,
                                count: group.candidates.count
                            ),
                            password: candidate.password
                        )
                    }
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Password to keep")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    selectionPicker
                        .labelsHidden()
                    passwordVisibilityButton
                }
                VStack(alignment: .leading, spacing: CrestSpacing.small) {
                    Text("Password to keep")
                        .font(.subheadline.weight(.medium))
                    selectionPicker
                        .labelsHidden()
                    passwordVisibilityButton
                }
            }

            if group.collapsedDuplicateRowCount > 0 {
                Label(
                    duplicateSummary,
                    systemImage: "doc.on.doc"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(CrestSpacing.large)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.16))
        }
        .accessibilityElement(children: .contain)
    }

    private var status: (title: LocalizedStringKey, systemImage: String, color: Color) {
        if group.requiresChoice {
            return (
                "Needs review",
                "exclamationmark.arrow.triangle.2.circlepath",
                .orange
            )
        }
        if group.hasExistingCredential {
            return ("Already saved", "checkmark.circle", .secondary)
        }
        return ("New", "plus.circle.fill", .green)
    }

    private var selectionPicker: some View {
        Picker("Password to keep", selection: selectionBinding) {
            if group.hasExistingCredential {
                Text("Keep current password")
                    .tag(BrowserCredentialImportSelection.existing)
            }
            ForEach(
                group.candidates.enumerated(),
                id: \.element.rowNumber
            ) { index, candidate in
                Text(
                    importedPasswordChoiceLabel(
                        index: index,
                        count: group.candidates.count
                    )
                )
                .tag(
                    BrowserCredentialImportSelection.imported(
                        rowNumber: candidate.rowNumber
                    )
                )
            }
            Text("Skip this account")
                .tag(BrowserCredentialImportSelection.skip)
        }
        .pickerStyle(.menu)
    }

    private var passwordVisibilityButton: some View {
        Button(
            revealsPasswords ? "Hide Passwords" : "View Passwords",
            systemImage: revealsPasswords ? "eye.slash" : "eye",
            action: togglePasswordVisibility
        )
        .buttonStyle(.borderless)
        .accessibilityIdentifier(
            "import-password-visibility-\(group.origin.host)"
        )
    }

    private func importedPasswordChoiceLabel(index: Int, count: Int) -> String {
        count == 1
            ? String(localized: "Use imported password")
            : String(localized: "Use imported password \(index + 1)")
    }

    private func importedPasswordLabel(index: Int, count: Int) -> LocalizedStringKey {
        count == 1 ? "Imported" : "Imported \(index + 1)"
    }

    private var duplicateSummary: String {
        let count = group.collapsedDuplicateRowCount
        return count == 1
            ? String(localized: "1 identical duplicate will be skipped.")
            : String(localized: "\(count) identical duplicates will be skipped.")
    }

    private var selectionBinding: Binding<BrowserCredentialImportSelection> {
        Binding(
            get: { group.selection },
            set: { selection in select(selection) }
        )
    }
}

private struct BrowserCredentialSearchField: View {
    let title: LocalizedStringKey
    @Binding var text: String
    let accessibilityIdentifier: String

    var body: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(title, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    text = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, CrestSpacing.small)
        #if os(macOS)
            .frame(height: 30)
        #else
            .frame(minHeight: 44)
        #endif
        .background(.quaternary, in: .rect(cornerRadius: CrestRadius.control))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct BrowserCredentialImportPasswordValue: View {
    let label: LocalizedStringKey
    let password: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CrestSpacing.medium) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 72, alignment: .leading)
            Text(verbatim: password)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .privacySensitive()
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Password value shown visually")
    }
}

extension View {
    @ViewBuilder
    fileprivate func browserCredentialImportReviewSizing() -> some View {
        #if os(macOS)
            frame(
                minWidth: 660,
                idealWidth: 720,
                minHeight: 520,
                idealHeight: 620
            )
        #else
            presentationDetents([.large])
        #endif
    }
}
