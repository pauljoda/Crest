import SwiftUI

struct BrowserSyncSettingsView: View {
    let browser: BrowserStore
    @Bindable var cloudSync: BrowserCloudSyncController

    @State private var confirmsUsingDevice = false
    @State private var confirmsUsingICloud = false
    @State private var confirmsPullingFromICloud = false

    var body: some View {
        BrowserSettingsPane(.sync) {
            Section("iCloud Sync", systemImage: "icloud") {
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

                    Button("Pull from iCloud…", systemImage: "icloud.and.arrow.down") {
                        confirmsPullingFromICloud = true
                    }
                    .disabled(!canSyncNow)
                    .accessibilityIdentifier("icloud-sync-pull")
                    .accessibilityHint("Downloads a fresh copy and merges it with this device’s content")
                }

                if let error = cloudSync.errorDescription {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("icloud-sync-error")
                }

                if let localError = browser.cloudSyncLocalErrorDescription {
                    Label(localError, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if cloudSync.skippedRecordCount > 0 {
                    Label(
                        "Some iCloud changes could not be read. Update Crest on all devices, then pull from iCloud.",
                        systemImage: "exclamationmark.icloud"
                    )
                    .foregroundStyle(.orange)
                }

                Text(
                    "Apple doesn’t expose the iCloud account email to Crest. Confirm both devices use the same Apple Account in System Settings; this page should show iCloud account Available on each device."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let conflict = cloudSync.conflict {
                Section("Choose Which Copy to Keep", systemImage: "doc.on.doc") {
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

            Section("Sync Monitor", systemImage: "waveform.path") {
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

            BrowserSyncContentScopeSection()

            Section("Diagnostics", systemImage: "stethoscope") {
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
            "Pull the Latest from iCloud?",
            isPresented: $confirmsPullingFromICloud,
            titleVisibility: .visible
        ) {
            Button("Pull and Merge") {
                Task { await cloudSync.pullFromICloud() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Crest will download all synced Spaces and browser content and merge them with this device. Newer changes and synced deletions will be applied. Content found only on this device will be kept unless it was explicitly deleted on another device."
            )
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
