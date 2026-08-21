import SwiftUI

struct BrowserWebKitFeatureFlagControls: View {
    @Binding var filter: BrowserWebKitFeatureFlagFilter

    let statuses: [BrowserWebKitFeatureStatus]
    let categories: [BrowserWebKitFeatureCategory]
    let canReset: Bool
    let requestReset: () -> Void

    var body: some View {
        VStack(spacing: CrestSpacing.small) {
            searchField

            HStack(spacing: CrestSpacing.small) {
                categoryPicker
                statusPicker
                Toggle("Changed Only", isOn: $filter.showsOnlyChanged)
                    .fixedSize()

                Spacer(minLength: CrestSpacing.small)

                Button(
                    "Reset All",
                    systemImage: "arrow.counterclockwise",
                    action: requestReset
                )
                .disabled(!canReset)
                .accessibilityIdentifier("webkit-feature-reset-all")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: CrestSpacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search feature flags", text: $filter.searchText)
                .textFieldStyle(.plain)
            if !filter.searchText.isEmpty {
                Button("Clear Search", systemImage: "xmark.circle.fill") {
                    filter.searchText = ""
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, CrestSpacing.small)
        .frame(height: 30)
        .background(.quaternary, in: .rect(cornerRadius: CrestRadius.control))
        .accessibilityIdentifier("webkit-feature-search")
    }

    private var categoryPicker: some View {
        Picker("Category", selection: $filter.category) {
            Text("All Categories").tag(BrowserWebKitFeatureCategory?.none)
            ForEach(categories) { category in
                Text(verbatim: category.title).tag(Optional(category))
            }
        }
        .frame(width: 160)
    }

    private var statusPicker: some View {
        Picker("Status", selection: $filter.status) {
            Text("All Statuses").tag(BrowserWebKitFeatureStatus?.none)
            ForEach(statuses) { status in
                Text(verbatim: status.title).tag(Optional(status))
            }
        }
        .frame(width: 150)
    }
}
