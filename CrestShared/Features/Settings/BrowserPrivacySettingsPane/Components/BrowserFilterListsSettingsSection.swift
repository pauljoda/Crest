import SwiftUI

/// The filter lists the device subscribes to, which every Space that blocks
/// applies: the catalog's, the ones the person added by address, and their own
/// filters. Lists download and update on their own.
struct BrowserFilterListsSettingsSection: View {
    let core: CrestCore

    @State private var newListAddress = ""
    @State private var addError: String?
    @State private var customFiltersDraft: String?
    @State private var customFiltersError: String?

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
        customListsSection
        customFiltersSection
    }

    // MARK: - Actions - Catalog

    private func row(_ state: FilterListState) -> some View {
        Toggle(isOn: isOn(state.list)) {
            VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                Text(state.list.title)
                if state.isOn, state.isFailing {
                    failingNote
                }
            }
        }
    }

    private var failingNote: some View { note("Couldn’t update") }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(CrestTypography.metadata)
            .foregroundStyle(CrestColor.textSecondary)
    }

    private func isOn(_ list: FilterList) -> Binding<Bool> {
        Binding {
            core.state.filterLists.lists.first { $0.list == list }?.isOn ?? false
        } set: { isOn in
            _ = try? core.send(SetFilterList(list: list, isOn: isOn))
        }
    }

    // MARK: - Actions - Lists the person added

    private var customListsSection: some View {
        Section {
            ForEach(core.state.filterLists.customLists, id: \.list.id) { state in
                customRow(state)
            }
            HStack {
                TextField("Filter list address", text: $newListAddress)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                    .onSubmit(addList)
                Button("Add", action: addList)
                    .disabled(newListAddress.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let addError {
                Text(addError)
                    .font(CrestTypography.metadata)
                    .foregroundStyle(CrestColor.textSecondary)
            }
        } header: {
            Text("Your Lists")
        } footer: {
            if let updated = lastUpdate {
                Text("Filter lists updated \(Text(updated, format: .relative(presentation: .named)))")
            }
        }
    }

    private func customRow(_ state: CustomFilterListState) -> some View {
        HStack {
            Toggle(isOn: isOn(state.list.id)) {
                VStack(alignment: .leading, spacing: CrestFormRowMetrics.titleSpacing) {
                    Text(state.title)
                    Text(state.list.url)
                        .font(CrestTypography.metadata)
                        .foregroundStyle(CrestColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if state.list.isOn, state.isTooLarge {
                        note("Too large to use")
                    } else if state.list.isOn, state.isFailing {
                        failingNote
                    }
                }
            }
            Button {
                _ = try? core.send(RemoveCustomFilterList(id: state.list.id))
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(CrestChromeButtonStyle())
            .accessibilityLabel("Remove \(state.title)")
            .help("Remove \(state.title)")
        }
    }

    private func isOn(_ id: UUID) -> Binding<Bool> {
        Binding {
            core.state.filterLists.customLists.first { $0.list.id == id }?.list.isOn ?? false
        } set: { isOn in
            _ = try? core.send(SetCustomFilterList(id: id, isOn: isOn))
        }
    }

    private func addList() {
        let address = newListAddress.trimmingCharacters(in: .whitespaces)
        guard !address.isEmpty else { return }
        do {
            _ = try core.send(AddCustomFilterList(id: UUID(), url: address))
            newListAddress = ""
            addError = nil
        } catch {
            if case .customFilterListLimitReached(let limit) = error {
                addError = String(localized: "You can add up to \(limit.limit) lists.")
            } else {
                addError = String(localized: "Enter an https address.")
            }
        }
    }

    /// When the most recently updated list that is on was brought up to date.
    private var lastUpdate: Date? {
        let lists = core.state.filterLists
        return
            (lists.lists.filter(\.isOn).compactMap(\.updatedAt)
            + lists.customLists.filter(\.list.isOn).compactMap(\.updatedAt)).max()
    }

    // MARK: - Actions - The person's own filters

    private var customFiltersSection: some View {
        // Read here, so the editor shows the filters again once the core keeps
        // what the person saved.
        let saved = core.state.filterLists.customFilters
        return Section {
            TextEditor(text: customFilters(saved: saved))
                .font(.system(.callout, design: .monospaced))
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .frame(minHeight: 120)
                .accessibilityLabel("My Filters")
            if customFiltersDraft != nil {
                HStack {
                    if let customFiltersError {
                        Text(customFiltersError)
                            .font(CrestTypography.metadata)
                            .foregroundStyle(CrestColor.textSecondary)
                    }
                    Spacer()
                    Button("Revert") {
                        customFiltersDraft = nil
                        customFiltersError = nil
                    }
                    Button("Save", action: saveCustomFilters)
                }
            }
        } header: {
            Text("My Filters")
        } footer: {
            Text("One rule per line, as filter lists write them.")
        }
    }

    private func customFilters(saved: String) -> Binding<String> {
        Binding {
            customFiltersDraft ?? saved
        } set: { text in
            customFiltersDraft = text == saved ? nil : text
        }
    }

    private func saveCustomFilters() {
        guard let draft = customFiltersDraft else { return }
        do {
            _ = try core.send(SetCustomFilters(text: draft))
            customFiltersDraft = nil
            customFiltersError = nil
        } catch {
            customFiltersError = String(localized: "These filters are too long to keep.")
        }
    }
}
