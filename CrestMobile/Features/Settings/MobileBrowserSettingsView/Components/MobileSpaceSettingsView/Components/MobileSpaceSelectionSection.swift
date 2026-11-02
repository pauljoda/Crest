import SwiftUI

/// The Spaces Space settings edits, one row each in picker order, a Sub-Space
/// indented under its primary. Tapping a row edits that Space, as choosing its
/// crest in the group's crest row does; a long press opens its menu, which
/// moves it, changes its group or deletes it.
struct MobileSpaceSelectionSection: View {
    let browser: BrowserStore
    @Binding var selectedSpaceID: UUID?
    let addSubSpace: (UUID) -> Void
    let requestGroupChange: (BrowserSpaceGroupChange) -> Void
    let requestDeletion: (BrowserSpaceDeletionRequest) -> Void

    var body: some View {
        Section {
            ForEach(browser.spaceGroups.flatMap { $0 }) { space in
                row(space)
            }

            HStack {
                Text("Order")
                Spacer()
                BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
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

    private func row(_ space: SpaceModel) -> some View {
        let isSelected = space.id == selectedSpaceID
        return Button {
            selectedSpaceID = space.id
        } label: {
            HStack {
                BrowserSpaceIdentityLabel(space: space)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, browser.isSubSpace(space) ? MobileSpaceSelectionMetrics.subSpaceIndent : 0)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("space-settings-row-\(space.id)")
        .contextMenu {
            Group {
                let order = BrowserSpaceOrderActions(browser: browser, spaceID: space.id)
                Button("Move Up", systemImage: "arrow.up", action: order.moveUp).disabled(!order.canMoveUp)
                Button("Move Down", systemImage: "arrow.down", action: order.moveDown).disabled(!order.canMoveDown)
                Divider()
                BrowserSpaceGroupMenuItems(
                    browser: browser, space: space, requestGroupChange: requestGroupChange, addSubSpace: addSubSpace)
                Divider()
                BrowserSpaceDeletionMenuItems(browser: browser, space: space, requestDeletion: requestDeletion)
            }
            .crestMenuActionLabelStyle()
        }
    }
}

private enum MobileSpaceSelectionMetrics {
    /// How far a Sub-Space's row sits in from its primary's: past the
    /// primary's icon, as a tab sits in a folder.
    static let subSpaceIndent: CGFloat = 28
}
