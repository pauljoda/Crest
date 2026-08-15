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

#Preview("Settings Pane Header Copy") {
    BrowserSettingsPaneHeaderCopy(destination: .advanced)
        .frame(width: 420)
}
