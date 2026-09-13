import SwiftUI

struct BrowserCredentialImportReviewView: View {
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

extension View {
    @ViewBuilder
    fileprivate func browserCredentialImportReviewSizing() -> some View {
        #if os(macOS)
            frame(
                minWidth: BrowserCredentialImportReviewMetrics.minimumWidth,
                idealWidth: BrowserCredentialImportReviewMetrics.idealWidth,
                minHeight: BrowserCredentialImportReviewMetrics.minimumHeight,
                idealHeight: BrowserCredentialImportReviewMetrics.idealHeight
            )
        #else
            presentationDetents([.large])
        #endif
    }
}
