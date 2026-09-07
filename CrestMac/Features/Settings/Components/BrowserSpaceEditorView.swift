import AppKit
import SwiftUI

struct BrowserSpaceEditorView: View {

    let browser: BrowserStore
    let space: BrowserSpace
    let section: BrowserSpaceEditorSection
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting
    let spacePicker: BrowserSpaceCustomizationPicker

    @State private var downloads = BrowserSpaceDownloadSettingsModel()

    var body: some View {
        Group {
            switch section {
            case .appearance:
                appearanceEditor
            case .settings:
                settingsForm
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appearanceEditor: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 620
            let dense = geometry.size.height < 640
            HStack(spacing: 0) {
                if wide {
                    BrowserSpaceAppearanceHero(
                        branding: branding.wrappedValue, symbol: symbol.wrappedValue,
                        name: currentSpace.name, space: currentSpace, editableName: name,
                        spacePicker: spacePicker
                    )
                    .frame(width: min(280, geometry.size.width * 0.38))
                    .padding(14)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: dense ? 12 : 18) {
                        if !wide {
                            BrowserInlineSpaceName(name: name, size: dense ? 26 : 30)
                            spacePicker
                        }
                        BrowserSpaceBrandingEditor(
                            branding: branding, symbol: symbol, previewName: currentSpace.name,
                            compact: !wide, showsPreview: false, dense: dense,
                            controlsBackground: Color(nsColor: .windowBackgroundColor)
                        )
                        .id(space.id)
                    }
                    .padding(dense ? 14 : 20)
                    .id("space-settings-appearance-top")
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .contentMargins(.trailing, 12, for: .scrollContent)
                .defaultScrollAnchor(.top, for: .initialOffset)
            }
        }
        .scrollsSpaceAppearancePages(anchorID: "space-settings-appearance-top")
        .accessibilityIdentifier("space-customization-controls")
    }

    private var settingsForm: some View {
        Form {
            BrowserSpaceSettingsSections(
                browser: browser,
                space: space,
                spaceAccess: spaceAccess,
                dataDeleter: dataDeleter,
                capabilities: BrowserSpaceSettingsCapabilities(
                    downloads: downloads.settings(for: currentSpace),
                    editsCrestPasswords: true
                )
            )
        }
        .crestSettingsForm(maxWidth: .infinity)
        .padding(.horizontal, CrestSpacing.section)
        .task(id: space.id) {
            downloads.refresh(for: space.id)
        }
    }

    private var name: Binding<String> {
        browser.spaceIdentityBinding(\.name, in: space)
    }

    private var symbol: Binding<String> {
        browser.spaceIdentityBinding(\.symbol, in: space)
    }

    private var branding: Binding<BrowserSpaceBranding> {
        browser.spaceBrandingBinding(in: space)
    }

    private var currentSpace: BrowserSpace {
        browser.liveSpace(space)
    }
}
