#if os(macOS)
    import SwiftUI

    struct BrowserGettingStartedExtensions: View {
        let openURL: (URL) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top, spacing: 20) {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(CrestBrandPalette.sage)
                        .padding(24).background(CrestBrandTheme.surface, in: .rect(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Scan installed Safari extensions").font(CrestTypography.display(28))
                        Text(
                            "On Mac, open Settings → Extensions and choose Scan Installed. Crest looks through installed apps for compatible Safari Web Extensions, then lets you review what to add."
                        )
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Install from an extension store").font(CrestTypography.display(28))
                    Text("Open an extension's page in either store to install it in Crest on Mac.")
                        .foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { storeButtons }
                        VStack(alignment: .leading, spacing: 12) { storeButtons }
                    }
                    #if !os(macOS)
                        Text("Extension installation is available in Crest for Mac.").font(.caption).foregroundStyle(
                            .secondary)
                    #endif
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Report compatibility issues").font(CrestTypography.sans(16, weight: .semibold))
                    Text(
                        "Crest works to support extensions from other browsers. Some use browser-specific features that may behave differently or aren't supported yet. If something breaks, report it on GitHub with the extension's name, store link, and what happened."
                    )
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Report an extension issue", systemImage: "arrow.up.right") {
                        openURL(URL(string: "https://github.com/pauljoda/Crest/issues")!)
                    }.buttonStyle(.crestSecondary)
                }
            }.padding(26).browserOnboardingPanel()
        }

        @ViewBuilder private var storeButtons: some View {
            storeButton(
                "Chrome Web Store", caption: "EXTENSIONS FOR CHROME", asset: "GuideChrome",
                url: "https://chromewebstore.google.com/")
            storeButton(
                "Firefox Add-ons", caption: "EXTENSIONS FOR FIREFOX", asset: "GuideFirefox",
                url: "https://addons.mozilla.org/firefox/extensions/")
        }

        private func storeButton(_ title: String, caption: LocalizedStringKey, asset: String, url: String)
            -> some View
        {
            Button {
                openURL(URL(string: url)!)
            } label: {
                HStack(spacing: 12) {
                    Image(asset).resizable().scaledToFit().frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(caption).font(CrestTypography.sans(8, weight: .bold)).tracking(1).foregroundStyle(
                            .secondary)
                        Text(title).font(CrestTypography.sans(14, weight: .semibold))
                    }
                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .background(CrestBrandTheme.surface, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(CrestBrandTheme.line))
            }.buttonStyle(.plain)
        }
    }

#endif
