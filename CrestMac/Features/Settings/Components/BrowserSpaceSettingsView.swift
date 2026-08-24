import AppKit
import SwiftUI

struct BrowserSpaceSettingsView: View {
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let requestedSpaceID: SpaceID?
    let requestRevision: Int

    @State private var selectedSpaceID: SpaceID?
    @State private var editorSection =
        BrowserSpaceEditorSection.appearance

    var body: some View {
        VStack(spacing: 0) {
            spaceToolbar
            Divider()

            if let space {
                let currentSpace = browser.liveSpace(space)
                if BrowserSettingsPrivacyPolicy.canRevealSpaceData(
                    in: currentSpace,
                    accessController: spaceAccess
                ) {
                    BrowserSpaceEditorView(
                        browser: browser,
                        space: space,
                        section: editorSection,
                        spaceAccess: spaceAccess,
                        dataDeleter: dataDeleter
                    )
                    .id(space.id)
                } else {
                    Form {
                        BrowserSettingsPrivateSpaceAccessSection(
                            space: currentSpace,
                            accessController: spaceAccess,
                            detail: "Unlock this Space before viewing its tab preview or changing its settings."
                        )
                    }
                    .crestSettingsForm(maxWidth: 560)
                }
            } else {
                ContentUnavailableView(
                    "Select a Space",
                    systemImage: "square.grid.2x2",
                    description: Text("Choose a Space to edit its identity and privacy policy.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .crestRepairsSpaceSelection($selectedSpaceID, in: browser)
        .onChange(of: requestRevision, initial: true) {
            applyRequestedSelection()
        }
    }

    private var spaceToolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent(compact: false)
            toolbarContent(compact: true)
        }
        .padding(.horizontal, CrestSpacing.medium)
        .frame(minHeight: 54)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("space-settings-toolbar")
    }

    private func toolbarContent(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            spacePageIdentity(compact: compact)

            if !compact {
                Divider()
                    .frame(height: 28)
            }

            spacePicker(compact: compact)
            Spacer(minLength: compact ? 2 : 8)
            sectionPicker(compact: compact)
            Spacer(minLength: compact ? 2 : 8)
            spaceActions(includesNewSpace: compact)

            if !compact {
                addSpaceButton
            }
        }
    }

    /// Spaces is the one pane whose identity lives inside its functional toolbar
    /// instead of above the scroll content, so it wears the brand tile and the
    /// display serif at the section size that fits a 54pt toolbar rather than
    /// ``BrowserSettingsPaneHeader``'s page size.
    private func spacePageIdentity(compact: Bool) -> some View {
        HStack(spacing: CrestSpacing.small) {
            CrestIconTile(
                systemImage: BrowserSettingsDestination.spaces.symbol,
                color: BrowserSettingsDestination.spaces.color,
                size: 30,
                symbolSize: 13,
                cornerRadius: CrestRadius.control
            )
            .accessibilityHidden(true)

            Text(BrowserSettingsDestination.spaces.title)
                .font(CrestTypography.displaySection)
                .foregroundStyle(CrestBrandTheme.textDisplay)
        }
        .frame(
            width: compact
                ? nil
                : BrowserSpaceCustomizationVisualPolicy.wideIdentityWidth,
            alignment: .leading
        )
        .frame(minHeight: 54, alignment: .leading)
        .fixedSize(horizontal: compact, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("settings-page-header")
    }

    private func spacePicker(compact: Bool) -> some View {
        Picker("Space", selection: $selectedSpaceID) {
            ForEach(browser.session.spaces) { space in
                BrowserSpaceIdentityLabel(space: space)
                    .accessibilityLabel("\(space.name), \(spaceSummary(space))")
                    .tag(Optional(space.id))
            }
        }
        .labelsHidden()
        .frame(
            width: compact
                ? BrowserSpaceCustomizationVisualPolicy.compactSpacePickerWidth
                : 190
        )
        .accessibilityLabel("Space")
        .accessibilityIdentifier("space-settings-picker")
    }

    private func sectionPicker(compact: Bool) -> some View {
        Picker("Space settings section", selection: $editorSection) {
            ForEach(BrowserSpaceEditorSection.allCases) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(
            width: compact
                ? BrowserSpaceCustomizationVisualPolicy.compactSectionPickerWidth
                : BrowserSpaceCustomizationVisualPolicy.sectionPickerWidth
        )
        .accessibilityIdentifier("space-settings-section-picker")
    }

    private func spaceActions(includesNewSpace: Bool) -> some View {
        Menu {
            Group {
                if let space {
                    moveSpaceCommands(space.id)
                }
                if includesNewSpace {
                    Divider()
                    Button("New Space", systemImage: "plus", action: addSpace)
                }
            }
            .crestMenuActionLabelStyle()
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .crestMenuActionLabelStyle()
        .accessibilityLabel("Space Actions")
    }

    private var addSpaceButton: some View {
        Button("New Space", systemImage: "plus", action: addSpace)
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("space-settings-add")
    }

    private func addSpace() {
        browser.addSpace()
        selectedSpaceID = browser.session.selectedSpaceID
    }

    private var space: BrowserSpace? {
        guard let selectedSpaceID else { return nil }
        return browser.session.space(id: selectedSpaceID)
    }

    private func spaceSummary(_ space: BrowserSpace) -> String {
        BrowserSettingsPrivacyPolicy.spacePickerSummary(
            for: browser.liveSpace(space),
            isDefault: browser.session.defaultSpaceID == space.id,
            accessController: spaceAccess
        )
    }

    @ViewBuilder
    private func moveSpaceCommands(_ spaceID: SpaceID) -> some View {
        if let index = browser.session.spaces.firstIndex(where: { $0.id == spaceID }) {
            Button("Move Up", systemImage: "arrow.up") {
                browser.moveSpaces(from: IndexSet(integer: index), to: index - 1)
            }
            .disabled(index == browser.session.spaces.startIndex)

            Button("Move Down", systemImage: "arrow.down") {
                browser.moveSpaces(from: IndexSet(integer: index), to: index + 2)
            }
            .disabled(index == browser.session.spaces.index(before: browser.session.spaces.endIndex))
        }
    }

    private func applyRequestedSelection() {
        guard requestRevision > 0,
            let requestedSpaceID,
            browser.session.space(id: requestedSpaceID) != nil
        else { return }
        selectedSpaceID = requestedSpaceID
    }
}
