import SwiftUI

struct BrowserLocalExtensionInstallView: View {
    let session: BrowserLocalExtensionInstallSession

    @State private var isAccessExpanded = true

    var body: some View {
        let phase = session.phase
        VStack(alignment: .leading, spacing: CrestSpacing.large) {
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
                    compatibilityIssues: compatibilityIssues
                )
            case .failed(let errorDescription):
                BrowserExtensionInstallErrorContent(
                    error: errorDescription
                )
            }

            Divider()
            actions(for: phase)
        }
        .padding(CrestSpacing.extraLarge)
        .frame(width: BrowserExtensionInstallMetrics.width)
        .interactiveDismissDisabled(session.isBusy)
    }

    @ViewBuilder
    private func header(
        for phase: BrowserLocalExtensionInstallPhase
    ) -> some View {
        HStack(alignment: .center, spacing: CrestSpacing.medium) {
            BrowserExtensionIconView(
                extensionID: phase.candidate?.id,
                spaceID: session.space.id,
                payload: phase.candidate?.iconPayload,
                size: BrowserExtensionsMetrics.installReviewIconSize
            )
            VStack(alignment: .leading, spacing: CrestSpacing.extraSmall) {
                Text(headerTitle(for: phase))
                    .font(.title3.weight(.semibold))
                if let candidate = phase.candidate {
                    Label(
                        verificationLabel(for: candidate),
                        systemImage: verificationSymbol(for: candidate)
                    )
                    .font(.caption)
                    .foregroundStyle(
                        candidate.format == .chromeCRX3
                            ? AnyShapeStyle(.green)
                            : AnyShapeStyle(.secondary)
                    )
                } else {
                    Text("Chrome CRX and Firefox XPI")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: CrestSpacing.medium)
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

            DisclosureGroup(isExpanded: $isAccessExpanded) {
                ScrollView {
                    VStack(alignment: .leading, spacing: CrestSpacing.medium) {
                        BrowserExtensionInstallAccessGroup(
                            title: "Permissions",
                            values: candidate.requestedPermissions,
                            emptyText:
                                "No additional browser permissions requested."
                        )
                        BrowserExtensionInstallAccessGroup(
                            title: "Website Access",
                            values: candidate.requestedHosts,
                            emptyText: "No website access requested."
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
                Button(action: session.install) {
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
