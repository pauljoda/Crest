import AppKit
import SwiftUI

struct BrowserSpaceEditorView: View {
    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar

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
                if usesLiveSidebar {
                    BrowserCrestStudioWorkspace(branding: branding, symbol: symbol, name: name)
                        .accessibilityIdentifier("space-customization-controls")
                } else {
                    appearanceEditor
                }
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
            HStack(alignment: .top, spacing: 0) {
                if wide {
                    VStack(spacing: 16) {
                        spacePicker
                        BrowserCrestStudioPreview(
                            branding: branding.wrappedValue, symbol: symbol.wrappedValue,
                            name: currentSpace.name, space: currentSpace,
                            heroSize: geometry.size.height < 480 ? 96 : 140,
                            sidebarHeight: max(100, min(230, geometry.size.height - 344)))
                        Spacer(minLength: 0)
                    }
                    .frame(width: min(280, geometry.size.width * 0.32))
                    .padding(14)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: dense ? 12 : 18) {
                        if !wide {
                            spacePicker
                        }
                        BrowserSpaceBrandingEditor(
                            branding: branding, symbol: symbol, previewName: currentSpace.name,
                            compact: !wide, showsPreview: !wide, editableName: name
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
