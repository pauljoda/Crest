import SwiftUI

/// The save prompt's two answers: the way out, and whatever the route says the
/// commit is right now.
struct BrowserCredentialSaveActions: View {
    let route: BrowserCredentialPromptRoute
    let space: BrowserSpaceIdentity?
    let metrics: BrowserCredentialPromptMetrics
    let isStacked: Bool
    let dismiss: () -> Void
    let perform: (BrowserCredentialPromptPrimaryAction) -> Void

    @ViewBuilder
    var body: some View {
        if isStacked {
            VStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
                primaryAction.frame(maxWidth: .infinity)
                dismissAction.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: BrowserCredentialPromptMetrics.saveActionSpacing) {
                dismissAction
                primaryAction
            }
        }
    }

    private var dismissAction: some View {
        Button(action: dismiss) {
            Text(route.dismissActionTitle)
        }
        .buttonStyle(.crestSecondary)
        .disabled(route.isBusy)
    }

    @ViewBuilder
    private var primaryAction: some View {
        if let busyLabel = route.busyAccessibilityLabel {
            ProgressView()
                .controlSize(.small)
                .frame(
                    minWidth: metrics.saveBusyIndicatorSize,
                    minHeight: metrics.saveBusyIndicatorSize
                )
                .accessibilityLabel(Text(busyLabel))
        } else if let action = route.primaryAction, let title = title(of: action) {
            Button {
                perform(action)
            } label: {
                Text(title)
            }
            .buttonStyle(.crestPrimary)
        }
    }

    /// The commit's title: just Save or Update where the Space shows beside
    /// the buttons, and otherwise the route's, which names it.
    private func title(of action: BrowserCredentialPromptPrimaryAction) -> LocalizedStringResource? {
        if !metrics.saveActionNamesSpace, let save = action.action, !route.offersSystemPasswords {
            return save.shortTitle
        }
        return route.primaryActionTitle(spaceName: space?.name)
    }
}
