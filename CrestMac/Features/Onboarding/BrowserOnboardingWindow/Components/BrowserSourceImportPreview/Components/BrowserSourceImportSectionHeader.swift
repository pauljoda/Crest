import SwiftUI

struct BrowserSourceImportSectionHeader: View {
    let title: String
    let tabs: [BrowserTab]
    let includedTabIDs: Set<TabID>
    let setIncluded: (Set<TabID>, Bool) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(includesAll ? "Leave all" : "Include all") {
                setIncluded(tabIDs, !includesAll)
            }
            .buttonStyle(.borderless)
            .font(.caption2)
        }
        .frame(height: 24)
    }

    private var tabIDs: Set<TabID> { Set(tabs.map(\.id)) }
    private var includesAll: Bool { tabIDs.isSubset(of: includedTabIDs) }
}

#Preview("Source Import Section Header") {
    BrowserSourceImportSectionHeader(
        title: "OPEN TABS",
        tabs: [BrowserImportPreviewFixture.currentTab],
        includedTabIDs: [BrowserImportPreviewFixture.currentTab.id],
        setIncluded: { _, _ in }
    )
    .frame(width: 320)
    .padding()
}
