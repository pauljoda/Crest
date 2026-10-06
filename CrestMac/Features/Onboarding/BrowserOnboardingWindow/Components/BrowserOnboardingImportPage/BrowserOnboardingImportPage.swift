import SwiftUI

struct BrowserOnboardingImportPage: View {
    let sources: [BrowserInstalledImportSource]
    let isSelected: (BrowserInstalledImportSource) -> Bool
    /// Whether setup looked for browsers it does not list, and how many it found.
    let hasLookedForUnlisted: Bool
    let unlistedCount: Int
    let isReading: Bool
    let isLocked: Bool
    let failure: BrowserOnboardingFailureText?
    let accessLabel: (BrowserInstalledImportSource) -> String
    let toggleSelection: (BrowserInstalledImportSource) -> Void
    let lookForUnlisted: () -> Void
    let beginManualSetup: () -> Void
    let continueImport: () -> Void
    let back: BrowserOnboardingBackAction

    var body: some View {
        VStack(spacing: 0) {
            // The browsers sit centered while they fit, and scroll once they don't,
            // so the footer stays in reach however many are installed.
            ViewThatFits(in: .vertical) {
                choices
                    .frame(maxHeight: .infinity)
                ScrollView { choices }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .frame(
                maxHeight: BrowserImportPreviewControls.usesAnchoredImportFooter
                    ? .infinity
                    : nil
            )

            HStack {
                if back.closes {
                    Button("Close", action: back.action)
                        .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                        .disabled(isLocked)
                        .accessibilityIdentifier("onboarding-import-close")
                } else {
                    Button("Back", action: back.action)
                        .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                        .disabled(isLocked)
                        .accessibilityIdentifier("onboarding-back")
                }
                Spacer()
                BrowserOnboardingImportSelectionAction(
                    hasSelection: sources.contains(where: isSelected),
                    skip: beginManualSetup,
                    continueImport: continueImport
                )
                .disabled(isLocked)
            }
            .padding(18)
            .background(BrowserOnboardingPalette.paper)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(BrowserOnboardingPalette.line)
                    .frame(height: 1)
            }
        }
        .background(BrowserOnboardingPalette.parchment)
    }

    private var choices: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text("IMPORT")
                    .font(
                        BrowserOnboardingTypography.sans(
                            11,
                            weight: .bold
                        )
                    )
                    .tracking(2.2)
                    .foregroundStyle(BrowserOnboardingPalette.coral)
                Text("Choose what to bring over")
                    .font(BrowserOnboardingTypography.display(40))
                    .foregroundStyle(BrowserOnboardingPalette.ink)
                Text(
                    "Crest found these browsers on your Mac. You’ll review every Space and tab next."
                )
                .font(
                    BrowserOnboardingTypography.sans(16, weight: .medium)
                )
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                .multilineTextAlignment(.center)
            }

            if sources.isEmpty, hasLookedForUnlisted {
                ContentUnavailableView(
                    "No Supported Browsers Found",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text(
                        "You can still set up Spaces manually."
                    )
                )
            } else if !sources.isEmpty {
                BrowserInstalledImportSourceGrid(
                    sources: sources,
                    isSelected: isSelected,
                    isLocked: isLocked,
                    accessLabel: accessLabel,
                    toggleSelection: toggleSelection
                )
            }

            BrowserOnboardingUnlistedBrowsers(
                hasLooked: hasLookedForUnlisted,
                foundCount: unlistedCount,
                isLocked: isLocked,
                look: lookForUnlisted
            )

            if isReading {
                ProgressView("Building your review…")
                    .controlSize(.large)
            }
            if let failure {
                Label {
                    BrowserOnboardingFailureMessage(message: failure)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .accessibilityIdentifier("onboarding-import-error")
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
    }
}

/// Looks for browsers setup does not list, and says where to ask for one it
/// cannot find.
private struct BrowserOnboardingUnlistedBrowsers: View {
    let hasLooked: Bool
    let foundCount: Int
    let isLocked: Bool
    let look: () -> Void

    var body: some View {
        if !hasLooked {
            Button("Browser not listed?", systemImage: "magnifyingglass", action: look)
                .buttonStyle(BrowserOnboardingSecondaryButtonStyle())
                .disabled(isLocked)
                .accessibilityHint("Looks for other browsers built on Chromium")
        } else {
            VStack(spacing: 6) {
                if foundCount == 0 {
                    Text("Crest couldn’t find another browser. Not every browser can be found.")
                        .font(BrowserOnboardingTypography.sans(13, weight: .medium))
                        .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                        .multilineTextAlignment(.center)
                }
                Link("Request a browser", destination: BrowserAboutLinks.browserRequest)
                    .font(BrowserOnboardingTypography.sans(13, weight: .bold))
                    .foregroundStyle(BrowserOnboardingPalette.coral)
            }
        }
    }
}
