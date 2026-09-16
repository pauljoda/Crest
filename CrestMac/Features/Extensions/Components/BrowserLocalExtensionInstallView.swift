import SwiftUI

struct BrowserLocalExtensionInstallView: View {
    let session: BrowserLocalExtensionInstallSession

    @State private var isAccessExpanded = true
    @State private var isSelectingSpaces = false
    @State private var accessReview = BrowserExtensionInstallationPermissionPolicy.Review()

    var body: some View {
        let phase = session.phase
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
            if isSelectingSpaces, session.phase.candidate != nil {
                BrowserExtensionInstallSpacesPage(
                    primarySpaceName: session.space.name, spaces: session.additionalSpaces,
                    selection: $accessReview.additionalSpaceIDs,
                    goBack: { isSelectingSpaces = false })
            } else {
                header(for: phase)

                switch phase {
                case .unavailable:
                    EmptyView()
                case .preparing:
                    HStack(spacing: CrestSpacing.medium) {
                        ProgressView()
                        VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                            Text("Inspecting extension package…")
                                .font(.callout.weight(.medium))
                            Text(
                                "Crest is validating the archive and reading its identity, requested access, and WebKit compatibility."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                case .review(let candidate, let errorDescription):
                    review(
                        candidate,
                        errorDescription: errorDescription
                    )
                case .installed(let name, let compatibilityIssues):
                    BrowserExtensionInstallCompletionContent(
                        name: name,
                        spaceName: session.space.name,
                        compatibilityIssues: compatibilityIssues,
                        additionalSpaceCount: session.installedAdditionalSpaceCount,
                        copyWarnings: session.installedCopyWarnings
                    )
                case .failed(let errorDescription):
                    BrowserExtensionInstallErrorContent(
                        error: errorDescription
                    )
                }

                if session.phase.candidate != nil {
                    Button("Install in other Spaces…") { isSelectingSpaces = true }
                        .disabled(session.isBusy)
                    if !accessReview.additionalSpaceIDs.isEmpty {
                        Text("Additional Spaces: \(accessReview.additionalSpaceIDs.count)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
                actions(for: phase)
            }
        }
        .onChange(of: session.phase.candidate?.id, initial: true) {
            if let candidate = session.phase.candidate { accessReview = candidate.accessReview }
        }
        .padding(CrestSpacing.extraLarge)
        .frame(width: BrowserExtensionInstallMetrics.width)
        .interactiveDismissDisabled(session.isBusy)
    }

    @ViewBuilder
    private func header(
        for phase: BrowserLocalExtensionInstallPhase
    ) -> some View {
        BrowserExtensionInstallHeader(
            title: headerTitle(for: phase),
            extensionID: phase.candidate?.id,
            spaceID: session.space.id,
            iconPayload: phase.candidate?.iconPayload
        ) {
            if let candidate = phase.candidate {
                Label(
                    verificationLabel(for: candidate),
                    systemImage: verificationSymbol(for: candidate)
                )
                .foregroundStyle(
                    candidate.format == .chromeCRX3
                        ? AnyShapeStyle(.green)
                        : AnyShapeStyle(.secondary)
                )
            } else {
                Text("Chrome CRX and Firefox XPI")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func review(
        _ candidate: BrowserLocalExtensionCandidate,
        errorDescription: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            if let description = candidate.displayDescription {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent(
                "Install In",
                value: "\(session.space.name) Space"
            )
            .font(.callout)
            LabeledContent("Package", value: candidate.format.displayName)
                .font(.callout)
            if let version = candidate.version {
                LabeledContent("Version", value: version)
                    .font(.callout)
            }

            Label {
                VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                    Text("Installed from this Mac")
                        .font(.callout.weight(.semibold))
                    Text(
                        "Crest copies this package into the selected Space. Local packages do not update automatically and do not receive verified native companion access."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } icon: {
                Image(systemName: "internaldrive")
            }

            if let issue = candidate.compatibility.blockingIssues.first {
                Label {
                    VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                        Text("Not available as a local package")
                            .font(.callout.weight(.semibold))
                        Text(issue.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
            }

            BrowserExtensionInstallConsentText()

            DisclosureGroup(isExpanded: $isAccessExpanded) {
                ScrollView {
                    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                        BrowserExtensionInstallAccessGroup(
                            title: "Permissions",
                            values: candidate.requestedPermissions,
                            emptyText:
                                "No additional browser permissions requested.",
                            choices: $accessReview.permissions,
                            defaultAllowance: accessReview.allowsPermission
                        )
                        BrowserExtensionInstallAccessGroup(
                            title: "Website Access",
                            values: candidate.requestedHosts,
                            emptyText: "No website access requested.",
                            choices: $accessReview.hosts,
                            defaultAllowance: accessReview.allowsHost
                        )
                        if !candidate.errors.isEmpty {
                            BrowserExtensionInstallAccessGroup(
                                title: "WebKit Compatibility Warnings",
                                values: candidate.errors,
                                emptyText: ""
                            )
                            .foregroundStyle(.orange)
                        }
                        if !candidate.compatibility.issues.isEmpty {
                            BrowserExtensionInstallAccessGroup(
                                title: "Crest Compatibility",
                                values: candidate.compatibility.issues
                                    .map(\.message),
                                emptyText: ""
                            )
                            .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(
                    maxHeight: BrowserExtensionInstallMetrics
                        .accessReviewMaximumHeight
                )
                .padding(.top, CrestSpacing.small)
            } label: {
                Label(
                    "Review Access and Compatibility",
                    systemImage: "hand.raised.fill"
                )
                .font(.callout.weight(.semibold))
            }

            if let errorDescription {
                Label(
                    errorDescription,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func actions(
        for phase: BrowserLocalExtensionInstallPhase
    ) -> some View {
        HStack {
            if case .failed = phase {
                Button(
                    "Choose Another…",
                    action: session.chooseAnotherPackage
                )
            }

            Spacer()

            switch phase {
            case .installed:
                Button("Done", action: session.dismiss)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            case .unavailable, .preparing, .failed:
                cancelButton
            case .review(let candidate, _):
                cancelButton
                Button(action: { session.install(review: accessReview) }) {
                    if session.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Adding extension")
                    } else {
                        Text("Add Extension")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    session.isInstalling || !candidate.compatibility.canRun
                )
            }
        }
    }

    private var cancelButton: some View {
        Button("Cancel", role: .cancel, action: session.dismiss)
            .disabled(session.isBusy)
    }

    private func headerTitle(
        for phase: BrowserLocalExtensionInstallPhase
    ) -> String {
        switch phase {
        case .review(let candidate, _):
            candidate.displayName
        case .installed(let name, _):
            name
        case .failed:
            String(localized: "Couldn’t Read Extension Package")
        case .preparing, .unavailable:
            String(localized: "Install Extension Package")
        }
    }

    private func verificationLabel(
        for candidate: BrowserLocalExtensionCandidate
    ) -> String {
        switch candidate.format {
        case .chromeCRX3:
            String(localized: "Chrome Web Store signature verified")
        case .firefoxXPI:
            String(localized: "Local Firefox package")
        case .safariCustom:
            String(localized: "Safari custom extension")
        }
    }

    private func verificationSymbol(
        for candidate: BrowserLocalExtensionCandidate
    ) -> String {
        switch candidate.format {
        case .chromeCRX3:
            "checkmark.seal.fill"
        case .firefoxXPI:
            "doc.zipper"
        case .safariCustom:
            "wand.and.sparkles"
        }
    }
}
