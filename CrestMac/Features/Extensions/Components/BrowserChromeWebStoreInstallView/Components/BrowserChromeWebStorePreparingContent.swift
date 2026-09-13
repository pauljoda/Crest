import SwiftUI

struct BrowserChromeWebStorePreparingContent: View {
    var body: some View {
        BrowserExtensionInstallPreparingContent(
            title: "Checking the extension…",
            detail: "Crest is downloading the signed CRX3 package and verifying its developer and Web Store signatures."
        )
    }
}
