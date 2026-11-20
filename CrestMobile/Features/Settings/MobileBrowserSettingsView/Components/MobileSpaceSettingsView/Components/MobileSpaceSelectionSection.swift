import SwiftUI

/// The Spaces Space settings edits, one row each in picker order, a Sub-Space
/// showing its primary's name. Tapping a row edits that Space, as choosing its
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
            ForEach(browser.availableSpaces) { space in
                row(space)
            }

            HStack {
                Text("Order")
                Spacer()
                BrowserSpaceOrderControls(browser: browser, spaceID: selectedSpaceID)
                BrowserSpaceAddButton {
                    do throws(Rejection) {
                        try browser.addSpace()
                        selectedSpaceID = browser.selectedSpaceID
                    } catch {
                        BrowserNoticeCenter.shared.post(.failure(error.explanation))
                    }
                }
            }
        } header: {
            Text("Spaces")
        }
    }

    private func row(_ space: SpaceModel) -> some View {
        let isSelected = space.id == selectedSpaceID
        return Button {
            selectedSpaceID = space.id
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    BrowserSpaceIdentityLabel(space: space)
                        .foregroundStyle(Color.primary)
                    if browser.isSubSpace(space) {
                        Text("Sub-Space of \(browser.primary(of: space).settings.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
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
