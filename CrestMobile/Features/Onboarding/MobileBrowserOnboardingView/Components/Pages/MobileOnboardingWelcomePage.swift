import SwiftUI

struct MobileOnboardingWelcomePage: View {
    let action: BrowserOnboardingWelcomeAction
    let primaryTitle: String
    let status: String
    let primaryAction: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 10) {
                        CrestStartPageMark().frame(width: 28, height: 32)
                        Text("Crest").font(.headline)
                    }
                    HStack(spacing: 16) {
                        ForEach(Array(BrowserSpaceBrandingPreset.curated.prefix(3).enumerated()), id: \.element.id) {
                            index, preset in
                            BrowserSpaceCrestIcon(
                                branding: preset.applying(to: BrowserSpaceAppearanceLanding.customStart), size: 72
                            )
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
                            .background(preset.colors[0].color, in: .rect(cornerRadius: 22))
                            .rotationEffect(.degrees(index == 0 ? -7 : index == 2 ? 7 : 0))
                            .offset(y: hasAppeared || reduceMotion ? (index == 1 ? -10 : 8) : 24)
                        }
                    }
                    .padding(.vertical, 16)
                    .accessibilityHidden(true)
                    Text("Welcome to Crest").font(CrestTypography.display(40))
                    Text("Keep work, personal browsing, and projects in separate Spaces.")
                        .font(.title3).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 20) {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Set up your Spaces").font(.headline)
                                Text("Choose a name, crest, and theme. Add more Spaces whenever you need them.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "square.grid.2x2").frame(width: 28).foregroundStyle(
                                CrestBrandPalette.coral)
                        }
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Try the browser").font(.headline)
                                Text("Practice pinning, saving, and organizing tabs after setup.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "hand.tap").frame(width: 28).foregroundStyle(CrestBrandPalette.sky)
                        }
                    }
                    .padding(20)
                    .browserOnboardingPanel()
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 580, minHeight: geometry.size.height - 96, alignment: .center)
                .frame(maxWidth: .infinity)
            }
        }
        .background(BrowserOnboardingPalette.parchment)
        .foregroundStyle(BrowserOnboardingPalette.ink)
        .safeAreaInset(edge: .bottom) {
            Button(action: primaryAction) {
                HStack {
                    if action == .checking { ProgressView() }
                    Text(primaryTitle)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.crestPrimary(tint: CrestBrandPalette.butter))
            .disabled(action == .checking)
            .accessibilityIdentifier(BrowserMobileAccessibilityID.welcomeContinue)
            .padding(20)
            .frame(maxWidth: 580)
            .frame(maxWidth: .infinity)
            .background(BrowserOnboardingPalette.parchment)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.8)) { hasAppeared = true }
        }
    }
}
