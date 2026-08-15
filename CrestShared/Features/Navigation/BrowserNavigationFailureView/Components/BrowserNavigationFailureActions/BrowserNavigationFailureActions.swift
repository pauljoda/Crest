import SwiftUI

struct BrowserNavigationFailureActions: View {
    let layout: BrowserNavigationFailureLayout
    let canGoBack: Bool
    let canProceed: Bool
    let showsDetails: Bool
    let accent: Color
    let retry: () -> Void
    let goBack: () -> Void
    let proceed: () -> Void
    let toggleDetails: () -> Void

    @ViewBuilder
    var body: some View {
        if layout == .compact {
            VStack(spacing: CrestSpacing.medium) {
                BrowserNavigationFailureRetryButton(
                    accent: accent,
                    action: retry
                )
                .frame(maxWidth: .infinity)

                if canProceed {
                    BrowserNavigationFailureProceedButton(action: proceed)
                        .frame(maxWidth: .infinity)
                }

                if canGoBack {
                    BrowserNavigationFailureBackButton(action: goBack)
                        .frame(maxWidth: .infinity)
                }

                BrowserNavigationFailureDetailsButton(
                    showsDetails: showsDetails,
                    action: toggleDetails
                )
                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: CrestSpacing.medium) {
                BrowserNavigationFailureDetailsButton(
                    showsDetails: showsDetails,
                    action: toggleDetails
                )

                if canGoBack {
                    BrowserNavigationFailureBackButton(action: goBack)
                }

                Spacer(minLength: CrestSpacing.extraExtraLarge)

                if canProceed {
                    BrowserNavigationFailureProceedButton(action: proceed)
                }

                BrowserNavigationFailureRetryButton(
                    accent: accent,
                    action: retry
                )
            }
        }
    }
}

#Preview("Navigation Failure Actions — Compact") {
    BrowserNavigationFailureActions(
        layout: .compact,
        canGoBack: true,
        canProceed: false,
        showsDetails: false,
        accent: .blue,
        retry: {},
        goBack: {},
        proceed: {},
        toggleDetails: {}
    )
    .padding()
}

#Preview("Navigation Failure Actions — Regular Details") {
    BrowserNavigationFailureActions(
        layout: .regular,
        canGoBack: true,
        canProceed: true,
        showsDetails: true,
        accent: .blue,
        retry: {},
        goBack: {},
        proceed: {},
        toggleDetails: {}
    )
    .padding()
}
