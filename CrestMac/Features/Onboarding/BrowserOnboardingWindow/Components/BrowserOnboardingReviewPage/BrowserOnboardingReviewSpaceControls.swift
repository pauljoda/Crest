import SwiftUI

struct BrowserOnboardingReviewSpaceControls: View {
    // MARK: - Static Variables

    /// Wide enough for a Space's symbol and a name of a dozen letters.
    static let pickerWidth: CGFloat = 200

    // MARK: - Variables

    let flow: BrowserOnboardingFlow
    let application: ImportSource?
    let spaces: [BrowserImportSpaceReview]
    let review: BrowserImportSpaceReview

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                BrowserOnboardingReviewSourcePicker(
                    applicationName: flow.review?.title ?? application?.title ?? "browser",
                    spaces: spaces,
                    currentSpaceID: review.id,
                    sourceSpaceName: review.sourceSpace.settings.name,
                    show: { flow.shownReviewSpaceID = $0 }
                )

                Image(systemName: review.isIncluded ? "arrow.down" : "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(
                        review.isIncluded
                            ? BrowserOnboardingPalette.coral
                            : BrowserOnboardingPalette.inkSoft
                    )
                    .frame(width: 28, height: 28)
                    .background(
                        BrowserOnboardingPalette.coral.opacity(review.isIncluded ? 0.16 : 0.06),
                        in: .circle
                    )
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)

                BrowserOnboardingReviewDestinationPicker(
                    spaces: flow.destinationSpaces,
                    destination: destinationBinding,
                    destinationName: flow.destinationName(
                        for: review.destination
                    )
                )
                .disabled(!review.isIncluded)
            }

            VStack(spacing: 0) {
                BrowserOnboardingReviewChoice(
                    title: "Import Space",
                    systemImage: "square.stack.fill",
                    accessibilityLabel: "Import this Space",
                    isOn: spaceInclusionBinding
                )
                .disabled(isOutOfRoom)

                if application?.suppliesPasswords == true {
                    Divider()
                    BrowserOnboardingReviewChoice(
                        title: flow.passwordCountLabel(for: review),
                        systemImage: "key.fill",
                        accessibilityLabel: "Import passwords for \(review.sourceSpace.settings.name)",
                        isOn: passwordInclusionBinding
                    )
                    .disabled(!review.isIncluded || review.record.passwordCount == 0)
                }

                if !review.extensions.isEmpty {
                    Divider()
                    BrowserOnboardingReviewChoice(
                        title: BrowserOnboardingSummary.extensionCount(
                            included: review.includedExtensionIDs.count,
                            total: review.extensions.count
                        ),
                        systemImage: "puzzlepiece.extension.fill",
                        accessibilityLabel: "Install extensions for \(review.sourceSpace.settings.name)",
                        isOn: extensionInclusionBinding
                    )
                    .disabled(!review.isIncluded)
                }
            }
            .padding(.horizontal, 12)
            .background(
                Color.primary.opacity(0.06),
                in: .rect(cornerRadius: 12, style: .continuous)
            )
            .frame(width: Self.pickerWidth)

            if isOutOfRoom {
                Text("No room for another Space")
                    .font(.caption)
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.pickerWidth)
            }
        }
        .frame(width: 228)
    }

    /// The Space would come in new, but Crest holds no more new Spaces.
    private var isOutOfRoom: Bool {
        !review.isIncluded && review.destination == .newSpace && (flow.review?.newSpaceCapacity ?? 1) == 0
    }

    private var destinationBinding: Binding<BrowserImportDestination> {
        Binding(
            get: { review.destination },
            set: { flow.setDestination($0, for: review.id) }
        )
    }

    private var spaceInclusionBinding: Binding<Bool> {
        Binding(
            get: { review.isIncluded },
            set: { flow.setSpaceIncluded($0, in: review.id) }
        )
    }

    private var passwordInclusionBinding: Binding<Bool> {
        Binding(
            get: { review.includesPasswords && review.record.passwordCount > 0 },
            set: { flow.setPasswordsIncluded($0, in: review.id) }
        )
    }

    private var extensionInclusionBinding: Binding<Bool> {
        Binding(
            get: { !review.includedExtensionIDs.isEmpty },
            set: { flow.setExtensionsIncluded($0, in: review.id) }
        )
    }
}

/// One choice the review makes for a Space: what it brings, and a switch.
private struct BrowserOnboardingReviewChoice: View {
    let title: LocalizedStringResource
    let systemImage: String
    let accessibilityLabel: LocalizedStringResource
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .frame(width: 16)
            }
            .font(BrowserOnboardingTypography.sans(11, weight: .semibold))
            .foregroundStyle(BrowserOnboardingPalette.inkSoft)
            .opacity(isEnabled ? 1 : 0.55)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(BrowserOnboardingPalette.coral)
        .frame(minHeight: 36)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}

private struct BrowserOnboardingReviewSourcePicker: View {
    let applicationName: String
    let spaces: [BrowserImportSpaceReview]
    let currentSpaceID: UUID
    let sourceSpaceName: String
    let show: (UUID) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text("From \(applicationName)")
                .font(.caption)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

            BrowserOnboardingReviewMenu {
                Picker("Source Space", selection: selection) {
                    ForEach(spaces) { item in
                        BrowserSpaceIdentityLabel(space: item.sourceSpace).tag(item.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                if let current = spaces.first(where: { $0.id == currentSpaceID }) {
                    BrowserSpaceIdentityLabel(space: current.sourceSpace)
                }
            }
            .accessibilityLabel("Source Space")
            .accessibilityValue(sourceSpaceName)
        }
    }

    private var selection: Binding<UUID> {
        Binding(
            get: { currentSpaceID },
            set: { show($0) }
        )
    }
}

private struct BrowserOnboardingReviewDestinationPicker: View {
    let spaces: [SpaceModel]
    @Binding var destination: BrowserImportDestination
    let destinationName: String

    var body: some View {
        VStack(spacing: 4) {
            Text("Into Crest")
                .font(.caption)
                .foregroundStyle(BrowserOnboardingPalette.inkSoft)

            BrowserOnboardingReviewMenu {
                Picker("Destination Space", selection: $destination) {
                    Text("New Space").tag(BrowserImportDestination.newSpace)
                    ForEach(spaces) { space in
                        BrowserSpaceIdentityLabel(space: space).tag(
                            BrowserImportDestination.existing(space.id)
                        )
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                if let space = spaces.first(where: { destination.spaceID == $0.id }) {
                    BrowserSpaceIdentityLabel(space: space)
                } else {
                    Text("New Space")
                }
            }
            .accessibilityLabel("Destination Space")
            .accessibilityValue(destinationName)
        }
    }
}

/// A Space menu as wide as the review's choices below it, so the route and
/// the choices line up.
private struct BrowserOnboardingReviewMenu<Content: View, Label: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                label()
                    .lineLimit(1)
                    .foregroundStyle(BrowserOnboardingPalette.coral)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(BrowserOnboardingPalette.inkSoft)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(width: BrowserOnboardingReviewSpaceControls.pickerWidth, height: 30)
            .background(
                Color.primary.opacity(0.06),
                in: .rect(cornerRadius: 9, style: .continuous)
            )
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}
