import AppKit
import SwiftUI

struct BrowserSpaceEditorView: View {

    let browser: BrowserStore
    let space: BrowserSpace
    let section: BrowserSpaceEditorSection
    let spaceAccess: BrowserSpaceAccessController
    let dataDeleter: any BrowserSpaceDataDeleting

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
        ViewThatFits(in: .horizontal) {
            wideAppearanceEditor
            appearanceForm(showsInlinePreview: true)
        }
    }

    private var wideAppearanceEditor: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("BRANDING PREVIEW")
                    .font(.caption2.weight(.semibold))
                    .tracking(1.3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)

                brandingPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
            .padding(CrestSpacing.medium)
            // A flexible preview can consume the editor's minimum width and make
            // this whole HStack overflow behind the outer Settings sidebar.
            .frame(width: BrowserSpaceCustomizationVisualPolicy.previewIdealWidth)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            appearanceForm(showsInlinePreview: false)
        }
        .frame(
            minWidth: BrowserSpaceCustomizationVisualPolicy.wideEditorMinimumWidth
        )
    }

    private func appearanceForm(showsInlinePreview: Bool) -> some View {
        Form {
            if showsInlinePreview {
                Section("Branding Preview") {
                    brandingPreview
                        .frame(height: 320)
                }
            }

            Section("Identity") {
                TextField("Name", text: name)
                    .accessibilityIdentifier("space-name-field")
            }

            // The forge carries its own step headings, so it takes a headerless
            // section rather than sitting under a second "Style" title.
            Section {
                BrowserSpaceBrandingEditor(
                    branding: branding,
                    symbol: symbol,
                    showsPreview: false
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, CrestSpacing.small)
            }
        }
        .crestSettingsForm(maxWidth: .infinity)
        .frame(
            minWidth: showsInlinePreview
                ? nil
                : BrowserSpaceCustomizationVisualPolicy.editorMinimumWidth,
            idealWidth: showsInlinePreview
                ? nil
                : BrowserSpaceCustomizationVisualPolicy.editorMinimumWidth,
            maxWidth: .infinity
        )
        .accessibilityIdentifier("space-customization-controls")
    }

    private var brandingPreview: some View {
        BrowserSpaceSidebarPreview(space: currentSpace)
            .accessibilityIdentifier("space-customization-preview")
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
