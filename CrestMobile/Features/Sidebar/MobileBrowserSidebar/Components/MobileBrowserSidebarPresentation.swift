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
                MobileBrowserSpaceListSheet(
                    request: request,
                    browser: configuration.browser,
                    pages: configuration.pages,
                    spaceAccess: configuration.spaceAccess,
                    selectTab: configuration.selectTab,
                    openURL: configuration.openURL
                )
            }
            .sheet(isPresented: configuration.showsPasswords) {
                MobilePasswordSettingsView(
                    browser: configuration.browser,
                    spaceAccess: configuration.spaceAccess
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
    }
}
