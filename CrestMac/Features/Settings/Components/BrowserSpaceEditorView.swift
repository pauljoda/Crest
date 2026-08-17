import AppKit
import SwiftUI

struct BrowserSpaceEditorView: View {

    let browser: BrowserStore
    let space: BrowserSpace
    let section: BrowserSpaceEditorSection
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

    @State private var synchronizing = false
    @State private var synchronizationError: String?
    @State private var updatingAccessPolicy = false
    @State private var asksWhereToSaveDownloads = false
    @State private var downloadDirectoryName = "Downloads"
    @State private var usesCustomDownloadDirectory = false
    @State private var downloadPreferenceError: String?

    var body: some View {
        Group {
            switch section {
            case .appearance:
                appearanceEditor
            case .settings:
                settingsForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appearanceEditor: some View {
        ViewThatFits(in: .horizontal) {
            wideAppearanceEditor
            appearanceForm(showsInlinePreview: true)
        }
    }

    private var wideAppearanceEditor: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BRANDING PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                brandingPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
            .padding(CrestSpacing.medium)
            // A flexible preview can consume the editor's minimum width and make
            // this whole HStack overflow behind the outer Settings sidebar.
            .frame(width: BrowserSpaceCustomizationVisualPolicy.previewIdealWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            appearanceForm(showsInlinePreview: false)
        }
        .frame(
            minWidth: BrowserSpaceCustomizationVisualPolicy.wideEditorMinimumWidth
        )
    }

    private func appearanceForm(showsInlinePreview: Bool) -> some View {
        Form {
            if showsInlinePreview {
                Section("Branding Preview") {
                    brandingPreview
                        .frame(height: 320)
                }
            }

            Section("Identity") {
                TextField("Name", text: name)
                    .accessibilityIdentifier("space-name-field")
            }

            // The forge carries its own step headings, so it takes a headerless
            // section rather than sitting under a second "Style" title.
            Section {
                BrowserSpaceBrandingEditor(
                    branding: branding,
                    symbol: symbol,
                    showsPreview: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, CrestSpacing.small)
            }
        }
        .crestSettingsForm(maxWidth: .infinity)
        .frame(
            minWidth: showsInlinePreview
                ? nil
                : BrowserSpaceCustomizationVisualPolicy.editorMinimumWidth,
            idealWidth: showsInlinePreview
                ? nil
                : BrowserSpaceCustomizationVisualPolicy.editorMinimumWidth,
            maxWidth: .infinity
        )
        .accessibilityIdentifier("space-customization-controls")
    }

    private var brandingPreview: some View {
        BrowserSpaceSidebarPreview(space: currentSpace)
            .accessibilityIdentifier("space-customization-preview")
    }

    private var settingsForm: some View {
        Form {
            Section("Browsing") {
                Picker(
                    "Search engine",
                    selection: browsingPreferenceBinding(\.searchProvider)
                ) {
                    ForEach(BrowserSearchProvider.allCases) { provider in
                        BrowserSearchProviderIdentityLabel(provider: provider)
                            .tag(provider)
                    }
                }
                .accessibilityIdentifier("space-search-provider")

                Picker(
                    "Archive current tabs",
                    selection: browsingPreferenceBinding(
                        \.currentTabCleanupPolicy
                    )
                ) {
                    ForEach(BrowserCurrentTabCleanupPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .accessibilityIdentifier("space-tab-cleanup-policy")

                Button("Clean Up Eligible Tabs Now", systemImage: "archivebox") {
                    browser.cleanupCurrentTabs(in: space.id)
                }
                .disabled(
                    currentSpace.browsingPreferences.currentTabCleanupPolicy == .never
                )

                Text("This policy applies only to \(currentSpace.name). Eligible tabs remain recoverable from Archive.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Downloads") {
                Toggle(
                    "Ask where to save each download",
                    isOn: askWhereToSaveDownloads
                )
                .accessibilityIdentifier("space-download-save-panel")

                LabeledContent("Download location") {
                    Text(downloadDirectoryName)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Choose Folder…", systemImage: "folder") {
                        chooseDownloadDirectory()
                    }
                    Button("Use Downloads", systemImage: "arrow.uturn.backward") {
                        resetDownloadDirectory()
                    }
                    .disabled(!usesCustomDownloadDirectory)
                }

                if let downloadPreferenceError {
                    Label(
                        downloadPreferenceError,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.red)
                }

                Text(
                    "This location belongs only to \(currentSpace.name) on this Mac. Opening a finished download opens the file directly; its menu also includes Show in Finder."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Private Space") {
                Toggle(
                    "Require device authentication to view this Space",
                    isOn: requiresAuthentication
                )
                .disabled(updatingAccessPolicy)
                .accessibilityIdentifier("private-space-toggle")

                if updatingAccessPolicy {
                    ProgressView("Updating Space protection…")
                        .controlSize(.small)
                }

                Text(
                    "Crest uses Face ID, Touch ID, or the normal device passcode or password. Private Spaces lock again when Crest leaves the foreground."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Crest Passwords") {
                Toggle(
                    "Use Crest Passwords in this Space",
                    isOn: browser.credentialPreferenceBinding(
                        \.isEnabled,
                        in: space
                    )
                )
                .accessibilityIdentifier("space-crest-passwords-enabled")

                Group {
                    Toggle(
                        "Sync this Space’s Crest passwords with iCloud Keychain",
                        isOn: iCloudSynchronization
                    )
                    .disabled(synchronizing)

                    if synchronizing {
                        ProgressView("Updating existing Keychain items…")
                            .controlSize(.small)
                    }

                    if let synchronizationError {
                        Label(
                            synchronizationError,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.red)
                    }

                    Text(
                        "Crest Passwords remain private to this Space. System Passwords and passkeys are provider-managed and may appear in any Space for the matching site."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .disabled(!currentSpace.credentialPreferences.isEnabled)

                if !currentSpace.credentialPreferences.isEnabled {
                    Text(
                        "Saved passwords stay in this Space and can still be viewed or deleted from Passwords settings."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            BrowserSpaceDeletionSection(
                browser: browser,
                spaceID: space.id,
                dataDeleter: dataDeleter
            )
        }
        .crestSettingsForm(maxWidth: .infinity)
        .padding(.horizontal, CrestSpacing.section)
        .task(id: space.id) {
            refreshDownloadPreferences()
        }
    }

    private var name: Binding<String> {
        browser.spaceIdentityBinding(\.name, in: space)
    }

    private var symbol: Binding<String> {
        browser.spaceIdentityBinding(\.symbol, in: space)
    }

    private var branding: Binding<BrowserSpaceBranding> {
        browser.spaceBrandingBinding(in: space)
    }

    private var currentSpace: BrowserSpace {
        browser.liveSpace(space)
    }

    private var requiresAuthentication: Binding<Bool> {
        Binding {
            currentSpace.accessPolicy.requiresAuthentication
        } set: { isRequired in
            Task { await updateAccessPolicy(isRequired: isRequired) }
        }
    }

    private func updateAccessPolicy(isRequired: Bool) async {
        updatingAccessPolicy = true
        defer { updatingAccessPolicy = false }

        if !isRequired {
            guard await spaceAccess.unlock(currentSpace) else { return }
        }
        let policy: BrowserSpaceAccessPolicy =
            isRequired
            ? .deviceOwnerAuthentication
            : .open
        browser.updateSpaceAccessPolicy(policy, in: space.id)
        if isRequired {
            spaceAccess.lock(space.id)
        }
    }

    private var iCloudSynchronization: Binding<Bool> {
        Binding {
            currentSpace.credentialPreferences.syncsCrestPasswordsWithICloud
        } set: { enabled in
            synchronizationError = nil
            synchronizing = true
            Task { @MainActor in
                defer { synchronizing = false }
                do {
                    try await browser.setCrestPasswordSynchronization(enabled, in: space.id)
                } catch {
                    synchronizationError = "Crest couldn’t update iCloud synchronization."
                }
            }
        }
    }

    private var askWhereToSaveDownloads: Binding<Bool> {
        Binding {
            asksWhereToSaveDownloads
        } set: { enabled in
            asksWhereToSaveDownloads = enabled
            BrowserPlatformDownloadPreferences.shared.setAsksWhereToSave(
                enabled,
                for: space.id
            )
        }
    }

    private func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Choose Download Folder for \(currentSpace.name)"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.resolvesAliases = true

        Task { @MainActor in
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let directory = panel.url else { return }
            do {
                try BrowserPlatformDownloadPreferences.shared.rememberDirectory(
                    directory,
                    for: space.id
                )
                downloadPreferenceError = nil
                refreshDownloadPreferences()
            } catch {
                downloadPreferenceError =
                    "Crest couldn’t retain access to this folder."
            }
        }
    }

    private func resetDownloadDirectory() {
        BrowserPlatformDownloadPreferences.shared.clearDirectory(for: space.id)
        downloadPreferenceError = nil
        refreshDownloadPreferences()
    }

    private func refreshDownloadPreferences() {
        let preferences = BrowserPlatformDownloadPreferences.shared
        asksWhereToSaveDownloads = preferences.asksWhereToSave(for: space.id)
        if let customName = preferences.directoryDisplayName(for: space.id) {
            downloadDirectoryName = customName
            usesCustomDownloadDirectory = true
        } else {
            downloadDirectoryName = "Downloads"
            usesCustomDownloadDirectory = false
        }
    }

    private func browsingPreferenceBinding<Value>(
        _ keyPath: WritableKeyPath<BrowserSpaceBrowsingPreferences, Value>
    ) -> Binding<Value> {
        browser.browsingPreferenceBinding(keyPath, in: space)
    }
}
