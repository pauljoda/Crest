import SwiftUI

/// The catalog's filter lists by group, each on or off as the level set it
/// unless the person turned it themselves, and when they were last updated,
/// with a way to update them now. Lists download and update on their own.
struct BrowserFilterListsSettingsSection: View {
    let core: CrestCore

    @Environment(\.filterListUpdater) private var filterListUpdater
    /// When the person last asked for an update, until a list arrives.
    @State private var requestedUpdate: Date?

    var body: some View {
        ForEach(FilterListGroup.all, id: \.self) { group in
            Section {
                ForEach(core.state.filterLists.lists.filter { $0.list.group == group }, id: \.list) { state in
                    row(state)
                }
            } header: {
                Text(group.title)
            }
        }
        Section {
            CrestSettingRow("Updated") {
                HStack(spacing: CrestSettingRowMetrics.controlSpacing) {
                    Text(updatedText)
                        .foregroundStyle(CrestColor.textSecondary)
                    Button("Update Now", action: updateNow)
                        .disabled(requestedUpdate != nil)
                        .accessibilityIdentifier("ad-blocking-update-now")
                }
            }
        }
        .onChange(of: lastUpdate) { requestedUpdate = nil }
    }

    // MARK: - Actions - Lists

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

    private func isOn(_ list: FilterList) -> Binding<Bool> {
        Binding {
            core.state.filterLists.lists.first { $0.list == list }?.isOn ?? false
        } set: { isOn in
            _ = try? core.send(SetFilterList(list: list, isOn: isOn))
        }
    }

    // MARK: - Actions - Updates

    /// When the most recently updated list that is on was brought up to date.
    private var lastUpdate: Date? {
        let lists = core.state.filterLists
        return
            (lists.lists.filter(\.isOn).compactMap(\.updatedAt)
            + lists.customLists.filter(\.list.isOn).compactMap(\.updatedAt)).max()
    }

    private var updatedText: String {
        if requestedUpdate != nil { return String(localized: "Updating…") }
        guard let lastUpdate else { return String(localized: "Not yet") }
        return lastUpdate.formatted(.relative(presentation: .named))
    }

    private func updateNow() {
        guard (try? core.send(RefreshFilterLists())) != nil else { return }
        requestedUpdate = .now
        guard let filterListUpdater else {
            requestedUpdate = nil
            return
        }
        Task {
            await filterListUpdater.check()
            requestedUpdate = nil
        }
    }
}
