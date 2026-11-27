import SwiftUI

struct BrowserPictureInPictureSettingsSection: View {
    // MARK: - Variables

    let previewSpace: SpaceModel?

    @Bindable private var preferences = BrowserAppPreferenceStore.shared
    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared

    // MARK: - Actions - Drawing

    var body: some View {
        Section("Picture in Picture") {
            preview
            Toggle("Show border", isOn: $appearance.showsPictureInPictureBorder)
                .accessibilityIdentifier("picture-in-picture-window-border")
            Toggle("Square corners", isOn: $appearance.usesSquarePictureInPictureCorners)
                .accessibilityIdentifier("picture-in-picture-square-corners")
            Toggle("When switching tabs", isOn: $preferences.automaticallyEntersPictureInPicture)
                .accessibilityIdentifier("automatic-picture-in-picture-toggle")
            Toggle("When switching apps", isOn: $preferences.floatsVideoOnAppSwitch)
            Toggle("When leaving Crest’s desktop", isOn: $preferences.floatsVideoOnDesktopSwitch)
            Toggle("Return video when its tab regains focus", isOn: $preferences.redocksVideoOnFocus)
        }
    }

    private var preview: some View {
        let frame = appearance.pictureInPictureAppearance
        return RoundedRectangle(cornerRadius: frame.videoCornerRadius, style: .circular)
            .fill(CrestBrandPalette.charcoalComponents.color)
            .overlay {
                Image(systemName: "play.rectangle")
                    .font(.title)
                    .foregroundStyle(CrestBrandPalette.paper)
            }
            .aspectRatio(16.0 / 9, contentMode: .fit)
            .frame(maxWidth: 268)
            .padding(frame.borderWidth)
            .background {
                BrowserWindowAtmosphere(space: previewSpace)
            }
            .clipShape(RoundedRectangle(cornerRadius: frame.cornerRadius, style: .circular))
            .frame(maxWidth: .infinity)
            .padding(.vertical, CrestSpacing.small)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Picture in Picture preview")
    }
}
