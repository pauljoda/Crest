import SwiftUI

/// The filter lists the device subscribes to, which every Space that blocks
/// applies. Lists download and update on their own.
struct BrowserFilterListsSettingsSection: View {
    let core: CrestCore

    var body: some View {
        ForEach(FilterListGroup.all, id: \.self) { group in
            Section {
                ForEach(core.state.filterLists.filter { $0.list.group == group }, id: \.list) { state in
                    row(state)
                }
            } header: {
                Text(group.title)
            } footer: {
                if group == FilterListGroup.all.last, let updated = lastUpdate {
                    Text("Filter lists updated \(Text(updated, format: .relative(presentation: .named)))")
                }
            }
        }
    }

    private func row(_ state: FilterListState) -> some View {
        Toggle(isOn: isOn(state.list)) {
            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(state.list.title)
                if state.isOn, state.isFailing {
                    Text("Couldn’t update")
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                }
            }
        }
    }

    /// When the most recently updated list that is on was brought up to date.
    private var lastUpdate: Date? {
        core.state.filterLists.filter(\.isOn).compactMap(\.updatedAt).max()
    }

    private func isOn(_ list: FilterList) -> Binding<Bool> {
        Binding {
            core.state.filterLists.first { $0.list == list }?.isOn ?? false
        } set: { isOn in
            _ = try? core.send(SetFilterList(list: list, isOn: isOn))
        }
    }
}
