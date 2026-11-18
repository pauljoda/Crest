import SwiftUI

/// Bringing tabs on iPhone and iPad, which cannot read other browsers: Crest
/// on a Mac brings them in, and iCloud brings the Spaces here.
struct MobileSetupBringPage: View {
    // MARK: - Actions - Drawing

    var body: some View {
        Form {
            Section {
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
                .padding(.vertical, CrestSpacing.medium)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("setup-bring-on-mac")
            } footer: {
                Text("You can still make and name Spaces on this device.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

enum MobileSetupBringPageMetrics {
    static let symbolSize: CGFloat = 36
}
