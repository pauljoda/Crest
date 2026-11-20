import SwiftUI

/// The build at a glance at the top of Settings, in the icon the person chose
/// and with the WebKit version the device runs pages in.
struct MobileSettingsBuildHeader: View {
    var body: some View {
        BrowserSettingsBuildSummary(engine: WebKitEngineBinding.version) {
            BrowserPlatformCurrentAppIcon()
        }
    }
}
