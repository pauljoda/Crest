import SwiftUI
import UIKit
import WebKit

/// The build at a glance at the top of Settings, in the icon the person chose
/// and with the WebKit version the device runs pages in.
struct MobileSettingsBuildHeader: View {
    private static let engine = (Bundle(for: WKWebView.self).infoDictionary?["CFBundleShortVersionString"] as? String)
        .map { "WebKit \($0)" }

    var body: some View {
        BrowserSettingsBuildSummary(icon: Image(iconPreview), engine: Self.engine)
    }

    /// The preview of the app icon the person chose, or Crest's own.
    private var iconPreview: String {
        UIApplication.shared.alternateIconName.map { $0 + "Preview" } ?? "CrestPreview"
    }
}
