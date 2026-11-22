import SwiftUI

/// What the chosen browser brings: each of its Spaces as it comes in, new,
/// joining the Space of the same name, or as a Sub-Space where it shared a
/// profile, and whether its passwords and extensions come too. Everything
/// comes in as it is; choosing a Space shows it in the preview.
struct BrowserSetupSourcePage: View {
    // MARK: - Variables

    let flow: BrowserOnboardingFlow
    @Binding var shownSpaceID: UUID?

    // MARK: - Actions - Drawing

    var body: some View {
        Form {
            Section {
                ForEach(flow.reviewSpaces.filter(\.isIncluded)) { review in
                    row(review)
                }
            } header: {
                BrowserSetupPageHeading(verbatim: flow.chosenSource?.title ?? flow.review?.title ?? "")
            }
            Section {
                if flow.passwordCount > 0 {
                    Toggle(isOn: Binding(get: { flow.includesPasswords }, set: flow.setPasswordsIncluded)) {
                        LabeledContent("Passwords", value: "\(flow.passwordCount)")
                    }
                    .accessibilityIdentifier("setup-import-passwords")
                }
                if flow.extensionCount > 0 {
                    Toggle(isOn: Binding(get: { flow.includesExtensions }, set: flow.setExtensionsIncluded)) {
                        LabeledContent("Extensions", value: "\(flow.extensionCount)")
                    }
                    .accessibilityIdentifier("setup-import-extensions")
                }
            } footer: {
                if flow.includesPasswords, flow.insecurePasswordCount > 0 {
                    Text("Passwords for sites without HTTPS come in, but Crest won’t fill them in.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ review: BrowserImportSpaceReview) -> some View {
        let shownID = flow.previewSpaceID(of: review)
        return Button {
            shownSpaceID = shownID
        } label: {
            HStack(spacing: CrestSpacing.medium) {
                if let space = flow.setupPreview?.space(id: shownID) {
                    BrowserSpaceSymbolArtwork(space: space, size: 26, lockSize: 7)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(review.customization.name.isEmpty ? review.record.shownName : review.customization.name)
                        .font(.body.weight(.semibold))
                    Text(detail(review))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: CrestSpacing.small)
                if shownSpaceID == shownID {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.crestFormRow)
        .accessibilityAddTraits(shownSpaceID == shownID ? .isSelected : [])
    }

    /// Where the Space comes in, and how many of its tabs.
    private func detail(_ review: BrowserImportSpaceReview) -> String {
        let tabs = review.includedTabIDs.count
        if let name = flow.duplicateDestinationName(for: review) {
            return String(localized: "Joins your \(name) · \(tabs) tabs")
        }
        if let lead = flow.reviewGroup(of: review).first, lead.id != review.id {
            return String(localized: "Sub-Space of \(lead.customization.name) · \(tabs) tabs")
        }
        return String(localized: "New Space · \(tabs) tabs")
    }
}
