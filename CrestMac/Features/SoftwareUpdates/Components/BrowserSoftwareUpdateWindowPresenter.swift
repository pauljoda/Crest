import SwiftUI

struct BrowserSoftwareUpdateWindowPresenter: View {
    let model: BrowserSoftwareUpdateModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: model.presentationRevision, initial: true) { _, revision in
                guard revision > 0 else { return }
                openWindow(id: BrowserSceneID.softwareUpdate.rawValue)
            }
    }
}
