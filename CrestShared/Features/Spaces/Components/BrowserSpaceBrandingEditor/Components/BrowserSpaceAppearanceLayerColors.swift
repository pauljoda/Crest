import SwiftUI

/// Keep layer colors beside the shape or pattern they affect, ahead of its gallery.
struct BrowserSpaceAppearanceLayerColors: View {
    @Binding var branding: BrowserSpaceBranding
    let page: BrowserSpaceAppearancePage

    var body: some View {
        VStack(spacing: 0) {
            switch page {
            case .shape:
                BrowserSpaceLayerColorPicker(
                    title: "Field color", branding: branding, selection: $branding.editorBackplateColorIndex)
            case .emblem, .layout:
                BrowserSpaceLayerColorPicker(
                    title: "Emblem color", branding: branding, selection: $branding.editorSymbolColorIndex)
            case .border:
                BrowserSpaceLayerColorPicker(
                    title: "Border color", branding: branding, selection: $branding.editorTrimColorIndex)
            case .division:
                BrowserSpaceLayerColorPicker(
                    title: "Field color", branding: branding, selection: $branding.editorBackplateColorIndex)
                BrowserSpaceLayerColorPicker(
                    title: "Second field color", branding: branding, selection: $branding.editorSecondaryFieldColorIndex
                )
            case .band:
                BrowserSpaceLayerColorPicker(
                    title: "Band color", branding: branding, selection: $branding.editorOrdinaryColorIndex)
            default:
                EmptyView()
            }
        }
    }
}
