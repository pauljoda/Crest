import AppKit
import SwiftUI

struct BrowserSpaceSettingsView: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar
    @Environment(\.browserSettingsSelectLiveSpace) private var liveSpaceSelection
    let browser: BrowserStore
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let requestedSpaceID: SpaceID?
    let requestRevision: Int

    @Environment(\.browserSettingsTabState) private var tabState
    @State private var localSelectedSpaceID: SpaceID?
    @State private var localEditorSection = BrowserSpaceEditorSection.appearance
    private var selectedSpaceID: SpaceID? {
        get { if let tabState { tabState.selectedSpaceID } else { localSelectedSpaceID } }
        nonmutating set {
            if let tabState { tabState.selectedSpaceID = newValue } else { localSelectedSpaceID = newValue }
        }
    }
    private var editorSection: BrowserSpaceEditorSection {
        get { tabState?.spaceEditorSection ?? localEditorSection }
        nonmutating set {
            if let tabState { tabState.spaceEditorSection = newValue } else { localEditorSection = newValue }
        }
    }

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
                        dataDeleter: dataDeleter,
                        spacePicker: BrowserSpaceCustomizationPicker(
                            spaces: browser.session.spaces, selectedSpaceID: space.id,
                            selectSpace: { selectEditedSpace($0) }, moveSpace: moveSpace,
                            addSpace: addSpace)
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
        .crestRepairsSpaceSelection(Binding(get: { selectedSpaceID }, set: { selectedSpaceID = $0 }), in: browser)
        .onChange(of: requestRevision, initial: true) {
            applyRequestedSelection()
        }
    }

    private func selectEditedSpace(_ id: SpaceID?) {
        selectedSpaceID = id
        if let id, id != browser.selectedSpace?.id { liveSpaceSelection?.select(id) }
    }

    private var spaceToolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent(compact: false)
            toolbarContent(compact: true)
            stackedToolbarContent
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
            spaceOrderControls
            addSpaceButton
        }
    }

    private var stackedToolbarContent: some View {
        VStack(spacing: CrestSpacing.small) {
            HStack {
                spacePageIdentity(compact: true)
                Spacer(minLength: CrestSpacing.small)
                spacePicker(compact: true)
                addSpaceButton
            }
            HStack {
                sectionPicker(compact: true)
                Spacer(minLength: CrestSpacing.small)
                spaceOrderControls
            }
        }
        .padding(.vertical, CrestSpacing.small)
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
        Picker("Space", selection: Binding(get: { editedSpaceID }, set: { selectEditedSpace($0) })) {
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
        Picker("Space settings section", selection: Binding(get: { editorSection }, set: { editorSection = $0 })) {
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

    private var spaceOrderControls: some View {
        BrowserSpaceOrderControls(browser: browser, spaceID: editedSpaceID)
    }

    private var addSpaceButton: some View {
        BrowserSpaceAddButton(action: addSpace)
    }

    private func addSpace() {
        browser.addSpace()
        selectedSpaceID = browser.session.selectedSpaceID
    }

    private func moveSpace(_ sourceID: SpaceID, to targetID: SpaceID) {
        let spaces = browser.session.spaces
        guard let source = spaces.firstIndex(where: { $0.id == sourceID }),
            let target = spaces.firstIndex(where: { $0.id == targetID }), source != target
        else { return }
        browser.moveSpaces(from: IndexSet(integer: source), to: target > source ? target + 1 : target)
    }

    private var editedSpaceID: SpaceID? {
        usesLiveSidebar ? browser.session.selectedSpaceID : selectedSpaceID
    }

    private var space: BrowserSpace? {
        guard let editedSpaceID else { return nil }
        return browser.session.space(id: editedSpaceID)
    }

    private func spaceSummary(_ space: BrowserSpace) -> String {
        BrowserSettingsPrivacyPolicy.spacePickerSummary(
            for: browser.liveSpace(space),
            isDefault: browser.session.defaultSpaceID == space.id,
            accessController: spaceAccess
        )
    }

    private func applyRequestedSelection() {
        guard requestRevision > (tabState?.spaceRouteRevision ?? 0),
            let requestedSpaceID,
            browser.session.space(id: requestedSpaceID) != nil
        else { return }
        tabState?.spaceRouteRevision = requestRevision
        selectedSpaceID = requestedSpaceID
    }
}
