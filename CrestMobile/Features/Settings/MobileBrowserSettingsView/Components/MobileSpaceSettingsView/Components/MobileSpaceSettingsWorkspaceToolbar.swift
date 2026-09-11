import SwiftUI

/// The tab workspace keeps Space selection and Appearance / Details visible
/// while the shared crest editor scrolls below it.
struct MobileSpaceSettingsWorkspaceToolbar: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: SpaceID?
    @Binding var section: BrowserSpaceEditorSection

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                identity
                spacePicker
                Spacer(minLength: 0)
                sectionPicker.frame(width: 220)
                addSpaceButton
            }
            VStack(spacing: 12) {
                HStack {
                    identity
                    Spacer(minLength: 0)
                    spacePicker
                    addSpaceButton
                }
                sectionPicker
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(BrowserSettingsCanvas.card)
        .accessibilityIdentifier("space-settings-toolbar")
    }

    private var identity: some View {
        HStack(spacing: 8) {
            CrestIconTile(
                systemImage: BrowserSettingsDestination.spaces.symbol,
                color: BrowserSettingsDestination.spaces.color,
                size: 30, symbolSize: 13, cornerRadius: CrestRadius.control
            )
            .accessibilityHidden(true)
            Text("Spaces").font(.headline)
        }
        .fixedSize()
    }

    private var spacePicker: some View {
        Picker("Space", selection: $selectedSpaceID) {
            ForEach(browser.session.spaces) { space in
                BrowserSpaceIdentityLabel(space: space).tag(Optional(space.id))
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .lineLimit(1)
        .accessibilityIdentifier("space-settings-picker")
    }

    private var sectionPicker: some View {
        Picker("Space settings section", selection: $section) {
            ForEach(BrowserSpaceEditorSection.allCases) { section in
                Text(LocalizedStringKey(section.title)).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("space-settings-section-picker")
    }

    private var addSpaceButton: some View {
        Button("New Space", systemImage: "plus") {
            browser.addSpace()
            selectedSpaceID = browser.session.selectedSpaceID
        }
        .labelStyle(.iconOnly)
        .accessibilityIdentifier("space-settings-add")
    }
}
