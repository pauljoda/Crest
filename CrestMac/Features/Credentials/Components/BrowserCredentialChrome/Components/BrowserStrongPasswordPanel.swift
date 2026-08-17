import SwiftUI

struct BrowserStrongPasswordPanel: View {
    let request: BrowserCredentialFillRequest
    let page: BrowserPage
    let browser: BrowserStore

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var model = BrowserStrongPasswordOperationModel()

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: BrowserCredentialChromeMetrics.strongPasswordSpacing
        ) {
            HStack(spacing: BrowserCredentialChromeMetrics.headerSpacing) {
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(space?.accent.color ?? .accentColor)
                    .accessibilityHidden(true)
                VStack(
                    alignment: .leading,
                    spacing: BrowserCredentialChromeMetrics.headerTextSpacing
                ) {
                    Text("Strong Password for \(spaceName)")
                        .font(.callout.weight(.semibold))
                    Text(request.origin.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
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
                    "This password form is embedded in \(request.topLevelOrigin.description).",
                    systemImage: "rectangle.inset.filled.and.person.filled"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Text(
                "Crest will fill a unique 20-character password into this form and its confirmation field. It is saved only after you submit and confirm the native \(spaceName) prompt."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button(action: generateAndFill) {
                if model.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(
                            minWidth: BrowserCredentialChromeMetrics.controlHitTarget,
                            minHeight: BrowserCredentialChromeMetrics.controlHitTarget
                        )
                        .accessibilityLabel("Creating strong password")
                } else {
                    Label(
                        "Use Strong Password",
                        systemImage: "key.horizontal.fill"
                    )
                    .frame(
                        minHeight: BrowserCredentialChromeMetrics.controlHitTarget
                    )
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(space?.accent.color ?? .accentColor)
            .disabled(model.isWorking)

            if model.hasFailed {
                Text("The form changed before Crest could fill the password.")
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Strong password for \(spaceName)")
        .accessibilityIdentifier("crest-strong-password")
    }

    private var space: BrowserSpace? {
        browser.session.space(id: page.spaceID)
    }

    private var spaceName: String {
        space?.name ?? "this Space"
    }

    private func generateAndFill() {
        Task { @MainActor in
            await model.generateAndFill { password in
                try await page.fillGeneratedPassword(password, for: request.id)
            }
        }
    }
}
