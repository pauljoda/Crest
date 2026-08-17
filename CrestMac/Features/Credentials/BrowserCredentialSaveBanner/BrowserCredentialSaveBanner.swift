import SwiftUI

struct BrowserCredentialSaveBanner: View {
    let candidate: BrowserCredentialSaveCandidate
    let page: BrowserPage
    let browser: BrowserStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var model = BrowserCredentialSavePromptModel()

    private var space: BrowserSpace? {
        browser.session.space(id: page.spaceID)
    }

    private var preferences: BrowserCredentialPreferences {
        space?.credentialPreferences ?? .default
    }

    private var route: BrowserCredentialPromptRoute {
        BrowserCredentialPromptRoute(
            phase: model.phase,
            systemPasswordOfferPhase: model.systemPasswordOfferPhase,
            offersSystemPasswords: false
        )
    }

    private var destination: BrowserCredentialPromptDestinationMetadata {
        route.destinationMetadata(
            spaceName: space?.name,
            syncsWithICloud: preferences.syncsCrestPasswordsWithICloud,
            presentation: .separateSyncStatus
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
                Spacer(minLength: 16)
                Button {
                    page.dismissCredentialSaveCandidate()
                } label: {
                    Text(route.dismissActionTitle)
                }
                .disabled(route.isBusy)
                primaryAction
            }

            HStack(spacing: 6) {
                if let space {
                    BrowserSpaceIdentityLabel(
                        space: space,
                        title: String(localized: destination.detail),
                        iconSize: 16
                    )
                } else {
                    Label(destination.detail, systemImage: "square.grid.2x2")
                }
                if let syncStatus = destination.syncStatus {
                    Text("·")
                    Label(syncStatus, systemImage: "icloud")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if candidate.isCrossOriginFrame {
                Text(
                    route.crossOriginMessage(
                        frameOrigin: candidate.origin,
                        topLevelOrigin: candidate.topLevelOrigin,
                        subject: .definiteCredential
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
        }
        .padding(12)
        .frame(maxWidth: 560)
        .background {
            BrowserAccessibleMaterialBackground(
                material: .regular,
                shape: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(
            color: .black.opacity(reduceTransparency ? 0 : 0.16),
            radius: 14,
            y: 6
        )
        .task(id: candidate.id) {
            await prepare()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(route.title(spaceName: space?.name)))
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let busyLabel = route.busyAccessibilityLabel {
            ProgressView()
                .controlSize(.small)
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
            break
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
            page.dismissCredentialSaveCandidate()
        }
    }
}
