import SwiftUI

struct MobilePasswordDescriptorList: View {
    @Bindable var model: MobilePasswordSettingsModel

    var body: some View {
        Group {
            if model.credentials.isLoading {
                ProgressView("Reading this Space’s Keychain…")
            } else if model.filteredDescriptors.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty
                        ? "No Saved Passwords"
                        : "No Matching Passwords",
                    systemImage: model.searchText.isEmpty
                        ? "key.slash"
                        : "magnifyingglass",
                    description: Text(
                        model.credentials.emptyDescription(
                            isSearching: !model.searchText.isEmpty
                        )
                    )
                )
            } else if let selectedSpace = model.selectedSpace {
                ForEach(model.filteredDescriptors) { descriptor in
                    BrowserPasswordDescriptorRow(
                        descriptor: descriptor,
                        space: selectedSpace,
                        isDeleting: model.credentials.isDeleting(descriptor),
                        showDetails: {
                            model.showDetails(descriptor)
                        },
                        requestDeletion: {
                            model.pendingDeletion = descriptor
                        }
                    )
                }
            }
        }
    }
}

#Preview {
    let fixture = MobileBrowserPreviewFixture()
    let model = MobilePasswordSettingsModel(
        browser: fixture.browser,
        spaceAccess: fixture.spaceAccess
    )
    Form {
        MobilePasswordDescriptorList(model: model)
    }
}
