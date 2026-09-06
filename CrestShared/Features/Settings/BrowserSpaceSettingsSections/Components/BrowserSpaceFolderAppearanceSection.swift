import SwiftUI

struct BrowserSpaceFolderAppearanceSection: View {
    let browser: BrowserStore
    let space: BrowserSpace

    var body: some View {
        Section("Sidebar") {
            Picker("Text Color", selection: browser.spaceBrandingBinding(in: space).textColorMode) {
                Label("Automatic", systemImage: "sparkles")
                    .tag(BrowserSpaceTextColorMode.automatic)
                Label("Light", systemImage: "sun.max.fill")
                    .tag(BrowserSpaceTextColorMode.light)
                Label("Dark", systemImage: "moon.fill")
                    .tag(BrowserSpaceTextColorMode.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("space-text-color-mode")
            CrestFormFootnote("Automatic chooses text contrast from this Space’s colors. Light and Dark override it.")
            LabeledContent("Folder color intensity") {
                HStack {
                    Slider(value: browser.spaceBrandingBinding(in: space).folderColorIntensity, in: 0...1)
                        .labelsHidden()
                        .accessibilityLabel("Folder color intensity")
                        .accessibilityIdentifier("space-folder-color-intensity")
                        .accessibilityValue(intensityLabel)
                    Text(intensityLabel)
                        .monospacedDigit()
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
            .accessibilityElement(children: .contain)
            CrestFormFootnote("Changes folder highlights in this Space, from the original transparency to solid color.")
            BrowserSpaceFolderAppearancePreview(space: browser.liveSpace(space))
        }
    }

    private var intensityLabel: String {
        let intensity = browser.liveSpace(space).branding.folderColorIntensity
        if intensity == 0 { return String(localized: "Subtle") }
        if intensity == 1 { return String(localized: "Opaque") }
        return intensity.formatted(.percent.precision(.fractionLength(0)))
    }
}
