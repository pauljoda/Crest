import SwiftUI

struct BrowserUtilityListSectionList: View {
    let sections: [BrowserUtilityListSection]
    let assignment: BrowserSpaceRuntimeAssignment
    let actions: BrowserUtilityListActions
    let dismissOnBlankSpace: (() -> Void)?

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.items) { item in
                        BrowserUtilityListRow(
                            item: item,
                            assignment: assignment,
                            actions: actions
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    Text(section.timeframe.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color.clear
                .contentShape(.rect)
                .onTapGesture {
                    dismissOnBlankSpace?()
                }
        }
        .environment(\.defaultMinListRowHeight, 1)
    }

}
