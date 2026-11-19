import SwiftUI

/// Bringing tabs: the browsers on this Mac, found by their apps without
/// reading their data. Choosing one reads it and pours its Spaces into the
/// preview as they come, everything as it is; choosing it again leaves it
/// out. The chosen browser opens its Spaces. Crest reads other browsers only
/// when the person chooses one or asks it to look for more.
struct BrowserSetupBringPage: View {
    // MARK: - Variables

    let flow: BrowserOnboardingFlow
    let open: () -> Void

    // MARK: - Actions - Drawing

    var body: some View {
        Form {
            Section {
                if flow.offeredSources.isEmpty, flow.hasScanned {
                    Text("Crest couldn’t find another browser. Not every browser can be found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(flow.offeredSources) { source in
                    row(source)
                }
            } header: {
                BrowserSetupPageHeading("Bring Tabs")
            }
            Section {
                if !flow.hasScanned {
                    Button("Look for Other Browsers", systemImage: "magnifyingglass", action: flow.scanForMore)
                        .buttonStyle(.crestSecondary)
                        .disabled(flow.isImportSelectionLocked)
                        .help("Looks through other browsers’ data on this Mac")
                        .accessibilityIdentifier("setup-scan")
                }
                if let failure = flow.failure?.message {
                    Label {
                        BrowserOnboardingFailureMessage(message: failure)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(CrestColor.danger)
                    .accessibilityIdentifier("setup-import-error")
                    if flow.chosenSource != nil {
                        Button("Try Again", systemImage: "arrow.clockwise", action: flow.readChosenSourceAgain)
                            .buttonStyle(.crestSecondary)
                            .disabled(flow.isImportSelectionLocked)
                            .accessibilityIdentifier("setup-import-retry")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func row(_ source: BrowserInstalledImportSource) -> some View {
        let isChosen = flow.isSelected(source)
        let isReady = isChosen && flow.hasIncomingSpaces
        return HStack(spacing: CrestSpacing.medium) {
            Button {
                flow.chooseSource(source)
            } label: {
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(CrestChromeButtonStyle())
            .disabled(flow.isImportSelectionLocked)
            .accessibilityLabel(Text("Bring tabs from \(source.title)"))
            .accessibilityValue(Text(isChosen ? "On" : "Off"))
            .accessibilityIdentifier("setup-source-\(source.application.name)")
            Button {
                if isReady { open() } else { flow.chooseSource(source) }
            } label: {
                HStack(spacing: CrestSpacing.medium) {
                    Image(nsImage: source.icon)
                        .resizable()
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.title)
                            .font(.body.weight(.semibold))
                        if isChosen { status }
                    }
                    Spacer(minLength: CrestSpacing.small)
                    if isReady { CrestFormDisclosureChevron() }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.browserSetupRow)
            .disabled(flow.isImportSelectionLocked && !isReady)
        }
    }

    @ViewBuilder
    private var status: some View {
        if flow.isReading {
            HStack(spacing: CrestSpacing.extraSmall) {
                ProgressView().controlSize(.mini)
                Text("Reading…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if let review = flow.review, flow.hasIncomingSpaces {
            Text(
                "^[\(review.spaces.filter(\.included).count) Space](inflect: true) · ^[\(review.includedTabCount) tab](inflect: true)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
