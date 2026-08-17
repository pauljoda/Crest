import SwiftUI

struct BrowserCredentialSuggestionPanel: View {
    let request: BrowserCredentialFillRequest
    let page: BrowserPage
    let browser: BrowserStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var model = BrowserCredentialSuggestionModel()
    @State private var fillErrorMessage: String?

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialChromeMetrics.suggestionSpacing
        ) {
            HStack(spacing: BrowserCredentialChromeMetrics.headerSpacing) {
                Image(systemName: "key.fill")
                    .foregroundStyle(space?.accent.color ?? .accentColor)
                    .accessibilityHidden(true)
                VStack(
                    alignment: .leading,
                    spacing: BrowserCredentialChromeMetrics.headerTextSpacing
                ) {
                    Text("Passwords in \(space?.name ?? "this Space")")
                        .font(.callout.weight(.semibold))
                    Text(request.origin.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: BrowserCredentialChromeMetrics.headerSpacerLength)
                Button(
                    "Close",
                    systemImage: "xmark",
                    action: page.dismissCredentialFillRequest
                )
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .frame(
                    width: BrowserCredentialChromeMetrics.controlHitTarget,
                    height: BrowserCredentialChromeMetrics.controlHitTarget
                )
            }

            if request.isCrossOriginFrame {
                Label(
                    "This sign-in frame is embedded in \(request.topLevelOrigin.description).",
                    systemImage: "rectangle.inset.filled.and.person.filled"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            if model.isLoading {
                ProgressView("Checking this Space…")
                    .controlSize(.small)
            } else if model.suggestions.isEmpty {
                Text("No Crest passwords are saved for this site in this Space.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.suggestions) { suggestion in
                    Button {
                        fill(suggestion)
                    } label: {
                        HStack(
                            spacing: BrowserCredentialChromeMetrics
                                .suggestionRowSpacing
                        ) {
                            Image(systemName: "person.crop.circle")
                                .foregroundStyle(.secondary)
                            Text(suggestion.username)
                                .lineLimit(1)
                            Spacer(
                                minLength: BrowserCredentialChromeMetrics
                                    .suggestionRowSpacerLength
                            )
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(.tint)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(
                        .vertical,
                        BrowserCredentialChromeMetrics.suggestionRowPadding
                    )
                }
            }

            if model.hasFailed {
                Text("Crest couldn’t read this Space’s passwords.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let fillErrorMessage {
                Text(fillErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(BrowserCredentialChromeMetrics.panelPadding)
        .frame(width: BrowserCredentialChromeMetrics.panelWidth)
        .background {
            BrowserAccessibleMaterialBackground(
                material: .regular,
                shape: RoundedRectangle(
                    cornerRadius: BrowserCredentialChromeMetrics.cornerRadius,
                    style: .continuous
                )
            )
        }
        .overlay {
            RoundedRectangle(
                cornerRadius: BrowserCredentialChromeMetrics.cornerRadius,
                style: .continuous
            )
            .strokeBorder(
                .separator,
                lineWidth: BrowserCredentialChromeMetrics.strokeWidth
            )
        }
        .shadow(
            color: .black.opacity(
                reduceTransparency
                    ? 0
                    : BrowserCredentialChromeMetrics.shadowOpacity
            ),
            radius: BrowserCredentialChromeMetrics.shadowRadius,
            y: BrowserCredentialChromeMetrics.shadowY
        )
        .task(id: request.id) {
            fillErrorMessage = nil
            await model.load(request, in: page.spaceID, using: browser)
        }
        .onDisappear(perform: model.cancel)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Crest password suggestions")
    }

    private var space: BrowserSpace? {
        browser.session.space(id: page.spaceID)
    }

    private func fill(_ descriptor: CredentialDescriptor) {
        Task { @MainActor in
            do {
                guard
                    let credential = try await browser.credential(
                        id: descriptor.id,
                        in: page.spaceID
                    )
                else {
                    fillErrorMessage = "That password is no longer available."
                    return
                }
                try await page.fillCredential(credential, for: request.id)
            } catch {
                fillErrorMessage = "The form changed before Crest could fill it."
            }
        }
    }
}
