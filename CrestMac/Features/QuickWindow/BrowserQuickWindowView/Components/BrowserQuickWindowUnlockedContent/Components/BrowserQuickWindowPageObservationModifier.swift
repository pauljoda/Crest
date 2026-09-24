import SwiftUI

struct BrowserQuickWindowPageObservationModifier: ViewModifier {
    let model: BrowserQuickWindowModel
    @Binding var addressText: String

    func body(content: Content) -> some View {
        content
            .onChange(of: model.page?.live.documentURL) { _, url in
                guard let url else { return }
                addressText = url.absoluteString
                model.updatePresentedURL(url)
            }
            .onChange(of: addressText) {
                model.recordUserActivity()
            }
    }
}
