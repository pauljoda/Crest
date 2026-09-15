import SwiftUI
import UIKit

/// Follows the icon selected for the Home Screen when About is displayed.
struct BrowserPlatformCurrentAppIcon: View {
    @State private var selectedName = UIApplication.shared.alternateIconName

    var body: some View {
        Image(selectedName.map { $0 + "Preview" } ?? "CrestPreview")
            .resizable()
            .scaledToFit()
            .onAppear { selectedName = UIApplication.shared.alternateIconName }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                selectedName = UIApplication.shared.alternateIconName
            }
    }
}
