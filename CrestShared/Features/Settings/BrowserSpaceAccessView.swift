import SwiftUI

struct BrowserSpaceAccessView: View {
    let space: BrowserSpace
    let spaces: [BrowserSpace]
    let accessController: BrowserSpaceAccessController
    let selectSpace: (BrowserSpaceRuntimeAssignment) -> Void
    var presentation: BrowserSpaceAccessPresentation = .standalone

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                accessContent
                    .frame(maxWidth: BrowserSpaceAccessLayout.maximumContentWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, presentation == .contentOverlay ? 28 : 44)
                    .frame(minHeight: geometry.size.height, alignment: .center)
            }
        }
        .background {
            accessBackground
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("private-space-lock")
    }

    private var accessContent: some View {
        VStack(spacing: 28) {
            VStack(spacing: 14) {
                BrowserSpaceSymbolArtwork(
                    space: space,
                    size: BrowserSpaceAccessLayout.iconSize,
                    lockSize: 16
                )

                VStack(spacing: 6) {
                    Text(space.name)
                        .font(.largeTitle.weight(.semibold))
                        .multilineTextAlignment(.center)

                    Label("Private Space", systemImage: "hand.raised.fill")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "Unlock with Face ID, Touch ID, or your device passcode or password. Until then, this Space’s tabs, site data, and credentials stay hidden."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await accessController.unlock(space) }
                } label: {
                    Label("Unlock \(space.name)", systemImage: "lock.open.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(accessController.authenticatingAssignment != nil)
                .accessibilityIdentifier("unlock-private-space")

                if accessController.isAuthenticating(space) {
                    ProgressView("Authenticating…")
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let failure = accessController.failure {
                    Label {
                        Text(failure.message)
                    } icon: {
                        Image(systemName: "exclamationmark.lock.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if presentation.showsSpaceMenu, spaces.count > 1 {
                    Divider()

                    Menu {
                        ForEach(spaces.filter { $0.id != space.id }) { candidate in
                            Button {
                                selectSpace(
                                    BrowserSpaceRuntimeAssignment(space: candidate)
                                )
                            } label: {
                                BrowserSpaceIdentityLabel(space: candidate)
                            }
                        }
                        .crestMenuActionLabelStyle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "square.grid.2x2")
                            Text("Switch Space")
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .crestMenuActionLabelStyle()
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .accessibilityIdentifier("switch-private-space")
                }
            }
        }
    }

    @ViewBuilder
    private var accessBackground: some View {
        ZStack {
            if presentation == .contentOverlay, !reduceTransparency {
                Rectangle().fill(.regularMaterial)
            } else {
                Rectangle().fill(.background)
            }
            BrowserSpaceBannerBackground(branding: space.branding)
                .opacity(reduceTransparency ? 0.04 : 0.1)
        }
        .ignoresSafeArea()
    }
}
