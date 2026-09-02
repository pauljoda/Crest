import SwiftUI

struct BrowserSpaceAccessView: View {
    let space: BrowserSpace
    let spaces: [BrowserSpace]
    let accessController: BrowserSpaceAccessController
    let selectSpace: (BrowserSpaceRuntimeAssignment) -> Void
    var presentation: BrowserSpaceAccessPresentation = .standalone

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            accessContent
                .frame(maxWidth: BrowserSpaceAccessLayout.maximumContentWidth)
                .padding(24)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top, for: .initialOffset)
        .defaultScrollAnchor(
            dynamicTypeSize.isAccessibilitySize ? .top : .center,
            for: .alignment
        )
        .background {
            accessBackground
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("private-space-lock")
    }

    private var accessContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                BrowserSpaceSymbolArtwork(
                    space: space,
                    size: BrowserSpaceAccessLayout.iconSize,
                    lockSize: 16
                )

                VStack(spacing: 6) {
                    Text(space.name)
                        .font(.title.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)

                    Label("Space Locked", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text("Unlock to view your tabs.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                Button {
                    Task { await accessController.unlock(space) }
                } label: {
                    BrowserSpaceAccessActionLabel(
                        isAuthenticating: accessController.isAuthenticating(space)
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(
                    maxWidth: dynamicTypeSize.isAccessibilitySize
                        ? .infinity : BrowserSpaceAccessLayout.maximumActionWidth
                )
                .disabled(accessController.authenticatingAssignment != nil)
                .accessibilityLabel(
                    accessController.isAuthenticating(space)
                        ? Text("Authenticating…") : Text("Unlock \(space.name)")
                )
                .accessibilityIdentifier("unlock-private-space")

                ZStack {
                    // Centered layouts reserve retry space. Accessibility layouts
                    // start at the top, so an error below cannot shift the button
                    // and empty message space need not lengthen the scroll.
                    if !dynamicTypeSize.isAccessibilitySize {
                        Text(BrowserSpaceAccessFailure.authenticationUnavailable.message)
                            .hidden()
                    }
                    if let failure = accessController.failure {
                        Text(failure.message)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                if presentation.showsSpaceMenu, spaces.count > 1 {
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
                        Label("Switch Space", systemImage: "square.grid.2x2")
                    }
                    .crestMenuActionLabelStyle()
                    .buttonStyle(.bordered)
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
