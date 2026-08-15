import SwiftUI

struct BrowserDataRetentionSettingsSection: View {
    let browser: BrowserStore
    let downloadCenter: BrowserDownloadCenter
    let spaceID: SpaceID

    @State private var pendingChange: BrowserDataRetentionChange?

    var body: some View {
        Section("Data retention") {
            ForEach(BrowserDataRetentionCategory.allCases) { category in
                Picker(category.title, selection: binding(for: category)) {
                    ForEach(BrowserDataRetentionDuration.allCases) { duration in
                        Text(duration.title).tag(duration)
                    }
                }
                .accessibilityIdentifier(category.accessibilityIdentifier)
            }

            Text(
                "Retention is set separately for this Space. Crest checks when it opens, after sync, and every 15 minutes while active. Download cleanup removes Crest’s record only; downloaded files stay on disk."
            )
            .crestFormFootnote()
        }
        .confirmationDialog(
            "Permanently delete older records?",
            isPresented: presentsConfirmation,
            titleVisibility: .visible
        ) {
            if let pendingChange {
                Button("Use \(pendingChange.proposed.title)", role: .destructive) {
                    apply(pendingChange)
                }
            }
            Button("Cancel", role: .cancel) {
                pendingChange = nil
            }
        } message: {
            if let pendingChange {
                Text(
                    "This immediately and permanently deletes \(pendingChange.category.cleanupDescription) older than \(pendingChange.proposed.title.lowercased()) in this Space, including synced copies. Downloaded files stay on disk."
                )
            }
        }
    }

    private var presentsConfirmation: Binding<Bool> {
        Binding(
            get: { pendingChange != nil },
            set: { isPresented in
                if !isPresented {
                    pendingChange = nil
                }
            }
        )
    }

    private func binding(
        for category: BrowserDataRetentionCategory
    ) -> Binding<BrowserDataRetentionDuration> {
        Binding(
            get: { policy(for: category) },
            set: { proposed in
                let change = BrowserDataRetentionChange(
                    category: category,
                    previous: policy(for: category),
                    proposed: proposed
                )
                guard change.previous != change.proposed else { return }
                if change.requiresConfirmation {
                    pendingChange = change
                } else {
                    apply(change)
                }
            }
        )
    }

    private func policy(
        for category: BrowserDataRetentionCategory
    ) -> BrowserDataRetentionDuration {
        guard
            let retention = browser.session.space(id: spaceID)?
                .browsingPreferences.dataRetention
        else {
            return .forever
        }
        return switch category {
        case .history: retention.history
        case .archive: retention.archive
        case .downloads: retention.downloads
        }
    }

    private func apply(_ change: BrowserDataRetentionChange) {
        guard
            var retention = browser.session.space(id: spaceID)?
                .browsingPreferences.dataRetention
        else {
            pendingChange = nil
            return
        }
        switch change.category {
        case .history: retention.history = change.proposed
        case .archive: retention.archive = change.proposed
        case .downloads: retention.downloads = change.proposed
        }
        let now = BrowserDataRetentionClock.now()
        browser.updateDataRetentionPreferences(retention, in: spaceID, now: now)
        downloadCenter.sweepExpiredRecords(
            using: browser.session,
            now: now,
            force: true
        )
        pendingChange = nil
    }
}

#Preview("Data Retention") {
    let browser = BrowserStore.preview()
    Form {
        BrowserDataRetentionSettingsSection(
            browser: browser,
            downloadCenter: BrowserDownloadCenter(),
            spaceID: browser.session.spaces[0].id
        )
    }
}
