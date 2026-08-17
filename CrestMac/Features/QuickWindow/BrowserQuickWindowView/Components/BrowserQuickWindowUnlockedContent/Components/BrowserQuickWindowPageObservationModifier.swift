import SwiftUI

struct BrowserQuickWindowPageObservationModifier: ViewModifier {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String

    func body(content: Content) -> some View {
        content
            .onChange(of: model.page?.completedNavigationCount) { oldCount, newCount in
                guard let newCount,
                    newCount > 0,
                    newCount != oldCount
                else { return }
                model.recordCompletedNavigation()
            }
            .onChange(of: model.page?.url) { _, url in
                guard let url else { return }
                addressText = url.absoluteString
                model.updatePresentedURL(url)
            }
            .onChange(of: addressText) {
                model.recordUserActivity()
            }
    }
}
