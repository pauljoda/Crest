import SwiftUI

/// Which of Crest's rows a page's context menu shows for a link or selected
/// text, and in what order, in the Links settings pane.
struct BrowserLinkMenuSettingsSection: View {
    @Bindable private var preferences = BrowserAppPreferenceStore.shared

    /// The row a person is dragging, while they drag one.
    @State private var dragged: LinkMenuRow?

    /// The rows, each with its switch and drag handle, then Reset Menu.
    var body: some View {
        Section {
            ForEach(preferences.linkMenu.rows, id: \.row) { choice in
                row(for: choice)
            }
            Button("Reset Menu") {
                preferences.linkMenu = .default
            }
            .disabled(preferences.linkMenu == .default)
            .accessibilityIdentifier("link-menu-reset")
        } header: {
            Text("Context Menu")
        } footer: {
            CrestFormFootnote("Drag to change the order.")
        }
    }

    /// A row's handle and name, and whether the menu shows it.
    private func row(for choice: LinkMenuChoice) -> some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Toggle(isOn: shows(choice.row)) {
                Text(choice.row.title)
            }
            .accessibilityIdentifier("link-menu-row-\(choice.row.name)")
        }
        .contentShape(.rect)
        .modifier(
            BrowserSettingsRowDrag(
                item: choice.row, name: choice.row.name, title: choice.row.title, dragged: $dragged
            ) { moving, target in
                preferences.linkMenu = preferences.linkMenu.moving(moving, to: target)
            }
        )
        .accessibilityActions {
            Button("Move Up") { move(choice, by: -1) }
            Button("Move Down") { move(choice, by: 1) }
        }
        .contextMenu {
            Button("Move Up") { move(choice, by: -1) }
                .disabled(choice.row == preferences.linkMenu.rows.first?.row)
            Button("Move Down") { move(choice, by: 1) }
                .disabled(choice.row == preferences.linkMenu.rows.last?.row)
        }
    }

    /// A switch for whether the menu shows `row`; turning it sends the change.
    private func shows(_ row: LinkMenuRow) -> Binding<Bool> {
        Binding {
            preferences.linkMenu.shows(row)
        } set: { isShown in
            preferences.linkMenu = preferences.linkMenu.showing(row, isShown)
        }
    }

    /// Moves `choice` one place up or down, as `offset`'s sign says.
    private func move(_ choice: LinkMenuChoice, by offset: Int) {
        guard let index = preferences.linkMenu.rows.firstIndex(where: { $0.row == choice.row }) else { return }
        let destination = offset < 0 ? max(0, index - 1) : min(preferences.linkMenu.rows.count, index + 2)
        preferences.linkMenu = preferences.linkMenu.moving(from: IndexSet(integer: index), to: destination)
    }
}
