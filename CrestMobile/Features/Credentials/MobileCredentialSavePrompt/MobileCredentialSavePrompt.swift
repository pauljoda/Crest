import SwiftUI

struct MobileCredentialSavePrompt: View {
    let candidate: BrowserCredentialSaveCandidate
    let page: MobileBrowserPage
    let browser: BrowserStore

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model = BrowserCredentialSavePromptModel()

    private var space: BrowserSpace? {
        browser.session.space(id: page.spaceID)
    }

    private var preferences: BrowserCredentialPreferences {
        space?.credentialPreferences ?? .default
    }

    private var shouldOfferSystemPasswords: Bool {
        BrowserSystemPasswordWriteThroughPolicy.shouldOffer(
            preferences: preferences,
            availability:
                BrowserSystemPasswordWriteThroughSystem.launchAvailability,
            isPrivateBrowsing: browser.isPrivateBrowsing
        )
    }

    private var route: BrowserCredentialPromptRoute {
        BrowserCredentialPromptRoute(
            phase: model.phase,
            systemPasswordOfferPhase: model.systemPasswordOfferPhase,
            offersSystemPasswords: shouldOfferSystemPasswords
        )
    }

    private var destination: BrowserCredentialPromptDestinationMetadata {
        route.destinationMetadata(
            spaceName: space?.name,
            syncsWithICloud: preferences.syncsCrestPasswordsWithICloud,
            presentation: .combinedStatus
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 9) {
                Image(systemName: candidate.passwordKind == .new ? "key.horizontal.fill" : "key.fill")
                    .font(.title3)
                    .foregroundStyle(space?.accent.color ?? .accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(route.title(spaceName: space?.name))
                        .font(.headline)
                    Text("\(candidate.username) · \(candidate.origin.description)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Group {
                if preferences.syncsCrestPasswordsWithICloud {
                    Label(destination.detail, systemImage: "icloud")
                } else if let space {
                    BrowserSpaceIdentityLabel(
                        space: space,
                        title: String(localized: destination.detail),
                        iconSize: 16
                    )
                } else {
                    Label(destination.detail, systemImage: "square.grid.2x2")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if candidate.isCrossOriginFrame {
                Text(
                    route.crossOriginMessage(
                        frameOrigin: candidate.origin,
                        topLevelOrigin: candidate.topLevelOrigin,
                        subject: .currentCredential
                    )
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if let errorMessage = route.errorMessage(spaceName: space?.name) {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if dynamicTypeSize.isAccessibilitySize {
                actionButtons.frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    actionButtons
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            BrowserAccessibleMaterialBackground(
                material: .regular,
                shape: Rectangle()
            )
        }
        .overlay(alignment: .bottom) { Divider() }
        .task(id: candidate.id) { await prepare() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(route.title(spaceName: space?.name)))
        .accessibilityIdentifier("crest-password-save")
    }

    @ViewBuilder
    private var actionButtons: some View {
        if route.primaryAction == .retrySystemPasswords {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) {
                    primaryAction.frame(maxWidth: .infinity)
                    dismissAction.frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: 8) {
                    dismissAction
                    primaryAction
                }
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                primaryAction.frame(maxWidth: .infinity)
                dismissAction.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 8) {
                dismissAction
                primaryAction
            }
        }
    }

    private var dismissAction: some View {
        Button {
            page.dismissCredentialSaveCandidate()
        } label: {
            Text(route.dismissActionTitle)
        }
        .disabled(route.isBusy)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let busyLabel = route.busyAccessibilityLabel {
            ProgressView()
                .controlSize(.small)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(Text(busyLabel))
        } else if let action = route.primaryAction,
            let title = route.primaryActionTitle(spaceName: space?.name)
        {
            Button {
                perform(action)
            } label: {
                Text(title)
            }
            .buttonStyle(.borderedProminent)
            .tint(space?.accent.color ?? .accentColor)
        }
    }

    private func perform(_ action: BrowserCredentialPromptPrimaryAction) {
        switch action {
        case .commit:
            save()
        case .retryCredentialPreparation:
            retry()
        case .retrySystemPasswords:
            retrySystemPasswords()
        }
    }

    private func prepare() async {
        await model.prepare(
            candidate: candidate,
            in: page.spaceID,
            browser: browser
        )
        guard !Task.isCancelled,
            page.credentialSaveCandidate?.id == candidate.id,
            model.phase == .alreadyStored
        else { return }
        page.dismissCredentialSaveCandidate()
    }

    private func retry() {
        Task { @MainActor in
            await prepare()
        }
    }

    private func save() {
        Task { @MainActor in
            await model.commit(
                candidate: candidate,
                in: page.spaceID,
                browser: browser
            )
            guard page.credentialSaveCandidate?.id == candidate.id,
                case .saved = model.phase
            else { return }
            guard shouldOfferSystemPasswords else {
                page.dismissCredentialSaveCandidate()
                return
            }
            await offerToSystemPasswords()
            guard model.systemPasswordOfferPhase == .completed else { return }
            page.dismissCredentialSaveCandidate()
        }
    }

    private func retrySystemPasswords() {
        Task { @MainActor in
            await offerToSystemPasswords()
            guard page.credentialSaveCandidate?.id == candidate.id,
                model.systemPasswordOfferPhase == .completed
            else { return }
            page.dismissCredentialSaveCandidate()
        }
    }

    private func offerToSystemPasswords() async {
        await model.offerToSystemPasswords {
            try await BrowserSystemPasswordWriteThroughSystem.offer(
                candidate: candidate,
                title: "\(candidate.username) · \(space?.name ?? "this Space")",
                anchor: page.webView.window
            )
        }
    }
}

#Preview("Save Password") {
    let fixture = MobileBrowserCredentialChromePreviewFixture()
    MobileCredentialSavePrompt(
        candidate: fixture.saveCandidate,
        page: fixture.page,
        browser: fixture.browser
    )
    .padding()
    .frame(width: 390)
}
