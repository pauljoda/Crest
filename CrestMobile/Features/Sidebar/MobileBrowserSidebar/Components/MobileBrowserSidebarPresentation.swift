import SwiftUI

struct MobileBrowserSidebarPresentation<Content: View>: View {
    let configuration: MobileBrowserSidebarPresentationConfiguration
    let content: Content

    init(
        configuration: MobileBrowserSidebarPresentationConfiguration,
        @ViewBuilder content: () -> Content
    ) {
        self.configuration = configuration
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.colorScheme, configuration.selectedColorScheme)
            .sheet(item: configuration.presentedSpaceSheet) { request in
                switch request.surface {
                case .archive:
                    MobileArchiveView(
                        browser: configuration.browser,
                        assignment: request.assignment,
                        spaceAccess: configuration.spaceAccess,
                        selectTab: configuration.selectTab
                    )
                case .history:
                    MobileHistoryView(
                        browser: configuration.browser,
                        assignment: request.assignment,
                        spaceAccess: configuration.spaceAccess,
                        openURL: configuration.openURL
                    )
                case .downloads:
                    MobileDownloadsView(
                        browser: configuration.browser,
                        pages: configuration.pages,
                        assignment: request.assignment,
                        spaceAccess: configuration.spaceAccess
                    )
                }
            }
            .sheet(isPresented: configuration.showsPasswords) {
                MobilePasswordSettingsView(
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess
                )
            }
            .sheet(isPresented: configuration.showsSettings) {
                MobileBrowserSettingsView(
                    browser: configuration.browser,
                    pages: configuration.pages,
                    spaceAccess: configuration.spaceAccess,
                    dataDeleter: configuration.dataDeleter
                )
            }
            .confirmationDialog(
                clearHistoryTitle,
                isPresented: clearHistoryConfirmationIsPresented,
                titleVisibility: .visible,
                presenting: configuration.clearHistoryConfirmation.wrappedValue
            ) { confirmation in
                Button("Clear History", role: .destructive) {
                    configuration.clearHistoryConfirmation.wrappedValue = nil
                    BrowserSidebarSpacePresentationPolicy.clearHistory(
                        confirmation,
                        in: configuration.browser,
                        accessController: configuration.spaceAccess
                    )
                }
            } message: { _ in
                Text("History in other Spaces is not affected.")
            }
            .onChange(of: configuration.utilityPresentation.surface) {
                previous,
                current in
                if previous != current {
                    configuration.utilitySearchText.wrappedValue = ""
                    configuration.utilityFilter.wrappedValue = .all
                }
                configuration.acknowledgeDownloads(current)
            }
            .onChange(of: configuration.selectedDownloadIDs) {
                configuration.acknowledgeDownloads(
                    configuration.utilityPresentation.surface
                )
            }
            .onChange(of: configuration.selectedSpaceAssignment) {
                _,
                assignment in
                guard let request = configuration.presentedSpaceSheet.wrappedValue,
                    request.assignment != assignment
                else { return }
                configuration.presentedSpaceSheet.wrappedValue = nil
            }
            .onChange(of: configuration.clearHistoryConfirmationIsLive) {
                _,
                isLive in
                guard !isLive else { return }
                configuration.clearHistoryConfirmation.wrappedValue = nil
            }
    }

    private var clearHistoryTitle: String {
        configuration.clearHistoryConfirmation.wrappedValue.map {
            "Clear history for \($0.spaceName)?"
        } ?? "Clear history?"
    }

    private var clearHistoryConfirmationIsPresented: Binding<Bool> {
        Binding {
            configuration.clearHistoryConfirmationIsLive
        } set: { isPresented in
            if !isPresented {
                configuration.clearHistoryConfirmation.wrappedValue = nil
            }
        }
    }
}
