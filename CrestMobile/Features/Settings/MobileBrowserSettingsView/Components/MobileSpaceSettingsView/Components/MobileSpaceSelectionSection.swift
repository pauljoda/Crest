import SwiftUI

/// The Spaces Space settings edits, one row per group in picker order: a
/// group's primary with its Sub-Spaces' crests stacked behind it. Tapping a
/// row edits the group, whose crest row then picks the Space; a long press
/// opens the group's menu, which moves it, changes it or deletes it.
struct MobileSpaceSelectionSection: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: UUID?
    let addSubSpace: (UUID) -> Void
    let requestGroupChange: (BrowserSpaceGroupChange) -> Void
    let requestDeletion: (BrowserSpaceDeletionRequest) -> Void

    var body: some View {
        Section {
            ForEach(browser.spaceGroups, id: \.[0].id) { group in
                row(group)
            }

            HStack {
                Text("Order")
                Spacer()
                BrowserSpaceOrderControls(browser: browser, spaceID: selectedGroupPrimaryID)
                BrowserSpaceAddButton {
                    browser.addSpace()
                    selectedSpaceID = browser.selectedSpaceID
                }
            }
        } header: {
            Text("Spaces")
        } footer: {
            BrowserSpaceGroupNoticeLabel()
        }
    }

    /// The primary of the group whose Space is edited.
    private var selectedGroupPrimaryID: UUID? {
        selectedSpaceID.flatMap { browser.spaceModel($0) }.map { browser.primary(of: $0).id }
    }

    private func row(_ group: [SpaceModel]) -> some View {
        let primary = group[0]
        let isSelected = primary.id == selectedGroupPrimaryID
        return Button {
            // Choosing the group being edited keeps the Space shown.
            if !isSelected { selectedSpaceID = primary.id }
        } label: {
            HStack {
                Label {
                    Text(primary.settings.name)
                } icon: {
                    BrowserSpaceGroupIcon(members: group, size: 20)
                }
                .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("space-settings-row-\(primary.id)")
        .contextMenu {
            let order = BrowserSpaceOrderActions(browser: browser, spaceID: primary.id)
            Button("Move Up", action: order.moveUp).disabled(!order.canMoveUp)
            Button("Move Down", action: order.moveDown).disabled(!order.canMoveDown)
            Divider()
            BrowserSpaceGroupMenuItems(
                browser: browser, space: primary, requestGroupChange: requestGroupChange, addSubSpace: addSubSpace)
            Divider()
            BrowserSpaceDeletionMenuItems(browser: browser, space: primary, requestDeletion: requestDeletion)
        }
    }
}
