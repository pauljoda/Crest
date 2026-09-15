import SwiftUI

struct BrowserSettingsPaneHeaderCopy: View {
    let destination: BrowserSettingsDestination

    var body: some View {
        VStack(spacing: 0) {
            Text(destination.title)
                .font(CrestTypography.displayPage)
                .foregroundStyle(CrestBrandTheme.textDisplay)
                .multilineTextAlignment(.center)

            Text(destination.subtitle)
                .crestFormFootnote()
                .multilineTextAlignment(.center)
                .padding(.top, BrowserSettingsPaneHeader.subtitleSpacing)
        }
    }
}

#if DEBUG
    #Preview("Component") {
        BrowserSettingsPaneHeaderCopy(destination: .privacy).padding().frame(width: 380)
    }
#endif
