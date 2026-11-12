import SwiftUI
import UIKit

/// Follows the icon selected for the Home Screen while it is displayed.
struct BrowserPlatformCurrentAppIcon: View {
    // MARK: - Static Variables

    /// Posted once Settings has changed the Home Screen icon, so every icon
    /// shown, such as the Start Page's under the Settings sheet, follows.
    static let didChange = Notification.Name("crest.app-icon.did-change")

    // MARK: - Variables

    @State private var selectedName = UIApplication.shared.alternateIconName

    var body: some View {
        BrowserPlatformAppIcon(name: selectedName)
            .onAppear { selectedName = UIApplication.shared.alternateIconName }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                selectedName = UIApplication.shared.alternateIconName
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.didChange)) { _ in
                selectedName = UIApplication.shared.alternateIconName
            }
    }
}
