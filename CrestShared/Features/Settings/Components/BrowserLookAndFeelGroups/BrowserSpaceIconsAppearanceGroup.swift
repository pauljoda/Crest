import SwiftUI

/// How the Space switcher shows every Space, as a preview button for icons
/// and one for dots, and how icons are sized where the page keeps that.
///
/// In Advanced the group holds only the sizing rows, which show while Space
/// icons are icons.
struct BrowserSpaceIconsAppearanceGroup: View {
    // MARK: - Variables

    @Bindable private var appearance = BrowserDeviceAppearanceStore.shared
    @Environment(\.browserAppearanceSettingFilter) private var filter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Actions - Drawing

    var body: some View {
        let showsSizing = filter.shows(.spaceIconSize) && !appearance.spaceIcons.showsDots
        if !filter.isAdvanced || showsSizing {
            CrestSettingsGroup("Space icons", settings: settings(showsSizing: showsSizing)) {
                if !filter.isAdvanced {
                    choices
                }
                if showsSizing {
                    sizing
                }
            }
        }
    }

    private var choices: some View {
        HStack(spacing: BrowserCustomizationStyleMetrics.spacing) {
            ForEach(BrowserSpaceIconDisplay.all) { display in
                CrestPreviewButton(
                    title: Text(display.title), isSelected: display == appearance.spaceIcons,
                    previewSize: BrowserSpaceIconsAppearanceMetrics.previewSize, faceSize: faceSize
                ) {
                    withAnimation(CrestMotion.styleChange.unlessReducingMotion(reduceMotion)) {
                        appearance.chosenSpaceIcons = display
                    }
                } preview: {
                    Color.clear.overlay(alignment: .bottomLeading) {
                        BrowserOnboardingWindowPreview(
                            branding: look.previewBranding, symbol: look.previewSymbol,
                            name: String(localized: "Personal"), spaceIcons: display, companionLook: look
                        ) {
                            EmptyView()
                        }
                        .frame(
                            width: BrowserCustomizationStyleMetrics.previewSize.width,
                            height: BrowserCustomizationStyleMetrics.previewSize.height
                        )
                    }
                }
                .accessibilityIdentifier("space-icons-\(display.name)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CrestSpacing.medium)
    }

    @ViewBuilder private var sizing: some View {
        CrestSettingRow("Fit Space icons to sidebar", setting: fits.resettable("Fit Space icons to sidebar")) {
            Toggle("Fit Space icons to sidebar", isOn: fits.binding)
                .labelsHidden()
                .accessibilityIdentifier("space-icons-fit-sidebar")
        }
        CrestSettingSlider(
            "Space icon size",
            value: scale,
            range: BrowserSpaceIconSizing.scaleRange,
            step: BrowserSpaceIconSizing.scaleStep,
            identifier: "space-icon-size"
        )
        .disabled(appearance.spaceIconSizing.fitsStrip)
    }

    // MARK: - Actions - Settings

    /// The look the previews wear: the style's own.
    private var look: SetupLook { appearance.customizationStyle.look }

    private var faceSize: CGFloat {
        sizeClass == .compact ? CrestPreviewButtonMetrics.compactFace : CrestPreviewButtonMetrics.regularFace
    }

    private var display: CrestResettableSetting {
        CrestResettableSetting(title: "Space icons", isDefault: appearance.chosenSpaceIcons == nil) {
            appearance.chosenSpaceIcons = nil
        }
    }

    /// Whether the Space switcher fits its icons to the sidebar, or keeps the
    /// size below.
    private var fits: CrestSettingValue<Bool> {
        CrestSettingValue(
            Binding(
                get: { appearance.spaceIconSizing.fitsStrip },
                set: { appearance.spaceIconSizing = $0 ? .automatic : .manual }
            ),
            default: BrowserLookAndFeelDefaults.spaceIconSizing.fitsStrip
        )
    }

    private var scale: CrestSettingValue<Double> {
        CrestSettingValue($appearance.spaceIconScale, default: BrowserLookAndFeelDefaults.spaceIconScale)
    }

    private func settings(showsSizing: Bool) -> [CrestResettableSetting] {
        (filter.isAdvanced ? [] : [display])
            + (showsSizing
                ? [fits.resettable("Fit Space icons to sidebar"), scale.resettable("Space icon size")] : [])
    }
}

enum BrowserSpaceIconsAppearanceMetrics {
    /// The part of a style's window a Space icons preview shows: the lower
    /// corner, where the switcher sits.
    static let previewSize = CGSize(width: 260, height: 260)
}
