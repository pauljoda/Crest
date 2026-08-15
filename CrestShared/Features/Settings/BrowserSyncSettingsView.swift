import SwiftUI

struct BrowserSyncSettingsView: View {
    let browser: BrowserStore
    @Bindable var cloudSync: BrowserCloudSyncController

    @State private var confirmsUsingDevice = false
    @State private var confirmsUsingICloud = false

    var body: some View {
        BrowserSettingsPane(.sync) {
            Section("iCloud Sync") {
                Toggle("Sync Crest with iCloud", isOn: $cloudSync.isEnabled)
                    .accessibilityIdentifier("icloud-sync-enabled")

                CrestSettingsStatusRow("Status") {
                    Label(cloudSync.phase.description, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                }
                CrestSettingsStatusRow("iCloud account") {
                    Text(cloudSync.accountState.description)
                        .foregroundStyle(.secondary)
                }

                if cloudSync.isEnabled {
                    Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                        Task { await cloudSync.syncNow() }
                    }
                    .disabled(!canSyncNow)
                    .accessibilityIdentifier("icloud-sync-now")
                }

                if let error = cloudSync.errorDescription {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("icloud-sync-error")
                }

                Text(
                    "Apple doesn’t expose the iCloud account email to Crest. Confirm both devices use the same Apple Account in System Settings; this page should show iCloud account Available on each device."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let conflict = cloudSync.conflict {
                Section("Choose Which Copy to Keep") {
                    Label(
                        "Crest found different content on this device and in iCloud. Sync is paused so neither copy is combined or overwritten without your choice.",
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                    )
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("icloud-sync-conflict")

                    LabeledContent(
                        "This device",
                        value: "\(conflict.localSpaceCount) Spaces, \(conflict.localRecordCount) records"
                    )
                    LabeledContent(
                        "iCloud",
                        value: "\(conflict.cloudSpaceCount) Spaces, \(conflict.cloudRecordCount) records"
                    )

                    Button("Use This Device", systemImage: "iphone.and.arrow.forward.outward") {
                        confirmsUsingDevice = true
                    }
                    .accessibilityHint("Replaces the Crest content in iCloud with this device’s content")

                    Button("Use iCloud", systemImage: "icloud.and.arrow.down") {
                        confirmsUsingICloud = true
                    }
                    .accessibilityHint("Replaces this device’s Crest content with the iCloud copy")
                }
            }

            Section("Sync Monitor") {
                LabeledContent("Local journal", value: localJournalStatus)
                LabeledContent(
                    "Local records",
                    value: (browser.syncCoordinator?.journal.records.count ?? 0).formatted()
                )
                LabeledContent(
                    "Pending uploads",
                    value: browser.pendingSyncRecordCount.formatted()
                )
                LabeledContent(
                    "Cloud records observed",
                    value: cloudSync.observedCloudRecordCount?.formatted() ?? "Not checked"
                )
                LabeledContent("Last attempt") {
                    optionalDate(cloudSync.lastAttemptAt)
                }
                LabeledContent("Last successful sync") {
                    optionalDate(cloudSync.lastSuccessAt)
                }
                LabeledContent(
                    "Last download batch",
                    value: cloudSync.lastFetchedRecordCount.formatted()
                )
                LabeledContent(
                    "Last upload batch",
                    value: cloudSync.lastUploadedRecordCount.formatted()
                )
            }

            Section("What Syncs") {
                SyncSettingsFactRow(
                    title: "Spaces and browser content",
                    detail:
                        "Space identity, pinned and saved tabs, current tabs, history, and archive records sync through Crest’s private CloudKit database.",
                    symbol: "square.stack.3d.up.fill"
                )
                SyncSettingsFactRow(
                    title: "Crest Passwords",
                    detail:
                        "Password values never enter CloudKit. Each Space’s separate iCloud Keychain switch controls those encrypted Keychain items.",
                    symbol: "key.fill"
                )
                SyncSettingsFactRow(
                    title: "Device-only data",
                    detail:
                        "Cookies, website data, service workers, downloads, and active page state stay on this device and remain isolated by Space.",
                    symbol: "internaldrive.fill"
                )
            }

            Section("Diagnostics") {
                LabeledContent(
                    "CloudKit container",
                    value: cloudSync.containerIdentifier ?? "Not configured"
                )
                ShareLink(
                    item: cloudSync.diagnosticsReport,
                    subject: Text("Crest iCloud Sync Diagnostics")
                ) {
                    Label("Share Diagnostics", systemImage: "square.and.arrow.up")
                }
                Text(
                    "The diagnostics report contains sync status and record counts, not URLs, titles, browsing history, passwords, or account identifiers."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(
            "Replace the iCloud Copy?",
            isPresented: $confirmsUsingDevice
        ) {
            Button("Replace iCloud with This Device", role: .destructive) {
                Task { await cloudSync.resolveUsingThisDevice() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Crest will upload this device’s Spaces and browser content over the current iCloud copy. Other devices will receive this version on their next sync."
            )
        }
        .confirmationDialog(
            "Replace This Device’s Copy?",
            isPresented: $confirmsUsingICloud
        ) {
            Button("Replace This Device with iCloud", role: .destructive) {
                Task { await cloudSync.resolveUsingICloud() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Crest will replace the synced Spaces and browser content on this device with the current iCloud copy.")
        }
    }

    private var canSyncNow: Bool {
        cloudSync.accountState == .available
            && cloudSync.conflict == nil
            && cloudSync.phase != .syncing
    }

    private var statusSymbol: String {
        switch cloudSync.phase {
        case .disabled: "icloud.slash"
        case .checking, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .ready: "checkmark.icloud.fill"
        case .needsReconciliation: "exclamationmark.icloud.fill"
        case .waitingForAccount: "person.crop.circle.badge.exclamationmark"
        case .failed: "xmark.icloud.fill"
        }
    }

    private var statusColor: Color {
        switch cloudSync.phase {
        case .ready: .green
        case .checking, .syncing: .blue
        case .needsReconciliation, .waitingForAccount: .orange
        case .failed: .red
        case .disabled: .secondary
        }
    }

    private var localJournalStatus: String {
        switch browser.localSyncCoordinatorStatus {
        case .ready: "Ready"
        case .recoveredCorruptLocalJournal: "Recovered after corruption"
        case nil: "Unavailable"
        }
    }

    @ViewBuilder
    private func optionalDate(_ date: Date?) -> some View {
        if let date {
            Text(date, style: .relative)
        } else {
            Text("Never")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Sync Settings") {
    let browser = BrowserStore.preview()
    BrowserSyncSettingsView(
        browser: browser,
        cloudSync: BrowserCloudSyncController.isolated(browser: browser)
    )
}
