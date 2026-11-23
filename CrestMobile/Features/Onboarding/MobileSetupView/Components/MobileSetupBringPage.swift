import SwiftUI

/// Bringing tabs on iPhone and iPad, which cannot read other browsers: Crest
/// on a Mac brings them in, and iCloud brings the Spaces here. The card sits
/// in the middle of the page, there being nothing else on it, and scrolls
/// when larger text makes it taller than the page.
struct MobileSetupBringPage: View {
    // MARK: - Variables

    @Environment(\.liesOnBrowserSetupPaper) private var liesOnPaper

    // MARK: - Actions - Drawing

    var body: some View {
        ScrollView {
            VStack(spacing: CrestSpacing.small) {
                VStack(spacing: CrestSpacing.large) {
                    HStack(spacing: CrestSpacing.large) {
                        Image(systemName: "laptopcomputer")
                        Image(systemName: "icloud.fill")
                            .foregroundStyle(.tint)
                        Image(systemName: "iphone")
                    }
                    .font(.system(size: MobileSetupBringPageMetrics.symbolSize, weight: .light))
                    .accessibilityHidden(true)
                    Text("Bring tabs in with Crest on your Mac")
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text(
                        "A Mac can read the browsers installed on it. Bring their Spaces and tabs into Crest there, and iCloud brings them here."
                    )
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(MobileSetupBringPageMetrics.cardInset)
                .background(
                    liesOnPaper ? BrowserSetupPaper.raisedFill : Color(uiColor: .secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: CrestRadius.panel, style: .continuous)
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(BrowserSetupAccessibilityID.bringOnMac)
                Text("You can still make and name Spaces on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, MobileSetupBringPageMetrics.pageInset)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Shorter than the page, the card sits in its middle; taller, it
        // scrolls from its top.
        .defaultScrollAnchor(.center, for: .alignment)
    }
}

enum MobileSetupBringPageMetrics {
    static let symbolSize: CGFloat = 36
    static let cardInset: CGFloat = 24
    static let pageInset: CGFloat = 20
}
