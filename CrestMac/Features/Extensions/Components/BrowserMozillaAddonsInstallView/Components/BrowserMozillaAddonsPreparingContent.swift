import SwiftUI

struct BrowserMozillaAddonsPreparingContent: View {
    var body: some View {
        BrowserExtensionInstallPreparingContent(
            title: "Checking the add-on…",
            detail:
                "Crest is downloading the add-on from Mozilla and checking it against the checksum, size, and identity Firefox Add-ons published for it."
        )
    }
}
