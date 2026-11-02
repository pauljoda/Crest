import SwiftUI

/// The tab workspace keeps Space selection and Appearance / Details visible
/// while the shared crest editor scrolls below it.
struct MobileSpaceSettingsWorkspaceToolbar: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: UUID?
    @Binding var section: BrowserSpaceEditorSection
    let addSubSpace: (UUID) -> Void
    let requestGroupChange: (BrowserSpaceGroupChange) -> Void
    let requestDeletion: (BrowserSpaceDeletionRequest) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                identity
                spacePicker
                Spacer(minLength: 0)
                sectionPicker.frame(width: 220)
                spaceOrderControls
                spaceActions
                addSpaceButton
            }
            VStack(spacing: 12) {
                HStack {
                    identity
                    Spacer(minLength: CrestSpacing.small)
                    spacePicker
                    spaceActions
                    addSpaceButton
                }
                HStack {
                    sectionPicker
                    Spacer(minLength: CrestSpacing.small)
                    spaceOrderControls
                }
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

    /// Every Space in picker order, each group in a section of its own, so
    /// choosing one here or in the crest row under the toolbar chooses it in
    /// both. Its own label keeps the selected Space's name on one line, shortened
    /// when the toolbar is narrow, so the actions beside it stay in view.
    private var spacePicker: some View {
        Menu {
            // One inline picker per group, which the menu separates.
            ForEach(browser.spaceGroups, id: \.[0].id) { group in
                Picker("Space", selection: $selectedSpaceID) {
                    ForEach(group) { space in
                        BrowserSpaceIdentityLabel(space: space).tag(Optional(space.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            HStack(spacing: 4) {
                if let space = selectedSpaceID.flatMap({ browser.spaceModel($0) }) {
                    BrowserSpaceIdentityLabel(space: space)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .layoutPriority(1)
        .accessibilityLabel("Space")
        .accessibilityValue(selectedSpaceID.flatMap { browser.spaceModel($0)?.settings.name } ?? "")
        .accessibilityIdentifier("space-settings-picker")
    }

    private var sectionPicker: some View {
        Picker("Space settings section", selection: $section) {
            ForEach(BrowserSpaceEditorSection.all) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("space-settings-section-picker")
    }

    /// What can be done to the selected Space's group: a new Sub-Space,
    /// joining or leaving a group, and deleting it.
    private var spaceActions: some View {
        Menu {
            if let space = selectedSpaceID.flatMap({ browser.spaceModel($0) }) {
                Group {
                    BrowserSpaceGroupMenuItems(
                        browser: browser, space: space, requestGroupChange: requestGroupChange,
                        addSubSpace: addSubSpace)
                    Divider()
                    BrowserSpaceDeletionMenuItems(browser: browser, space: space, requestDeletion: requestDeletion)
                }
                .crestMenuActionLabelStyle()
            }
        } label: {
            Label("Space Actions", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
                .frame(width: CrestLayout.minimumHitTarget, height: CrestLayout.minimumHitTarget)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(selectedSpaceID == nil)
        .accessibilityIdentifier("space-settings-actions")
    }

    private var addSpaceButton: some View {
        BrowserSpaceAddButton {
            browser.addSpace()
            selectedSpaceID = browser.selectedSpaceID
        }
    }

    private var spaceOrderControls: some View {
        BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
    }
}
