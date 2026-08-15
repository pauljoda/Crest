import Foundation
import UIKit

@MainActor
enum BrowserPlatformDefaultBrowserSystem {
    static let requestStyle = BrowserDefaultBrowserRequestStyle.systemSettings

    static func checkStatus() throws -> Bool {
        try UIApplication.shared.isDefault(.webBrowser)
    }

    static func requestDefault() async throws {
        openSettings()
    }

    static func openSettings() {
        guard let url = URL(
            string: UIApplication.openDefaultApplicationsSettingsURLString
        ) else { return }
        UIApplication.shared.open(url)
    }
}
