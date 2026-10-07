import AppKit
import SwiftUI

/// The build at a glance over the Settings sidebar, in the icon the person
/// chose and with the engine the build runs pages in.
struct BrowserSettingsBuildHeader: View {
    @Environment(\.browserMacWindows) private var windows

    var body: some View {
        BrowserSettingsBuildSummary(
            icon: Image(nsImage: NSApplication.shared.applicationIconImage), engine: windows?.engineCredits
        )
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}
