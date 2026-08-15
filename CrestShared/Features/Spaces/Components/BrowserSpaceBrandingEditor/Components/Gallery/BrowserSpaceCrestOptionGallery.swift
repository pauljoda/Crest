import SwiftUI

/// A forge gallery that redraws the current crest with one layer swapped.
struct BrowserSpaceCrestOptionGallery<
    Option: Hashable & BrowserSpaceHeraldicTerm
>: View {
    @Binding var branding: BrowserSpaceBranding
    let options: [Option]
    let keyPath: WritableKeyPath<BrowserSpaceCrest, Option>
    let compact: Bool
    var regularMinimumWidth = BrowserSpaceForgeMetrics.crestCardMinimumWidth
    var compactMinimumWidth = BrowserSpaceForgeMetrics.compactCrestCardMinimumWidth
    var iconSize = BrowserSpaceForgeMetrics.crestThumbnailSize

    var body: some View {
        BrowserSpaceOptionGallery(
            options: options,
            minimumWidth: compact ? compactMinimumWidth : regularMinimumWidth,
            isSelected: { option in
                option == branding.crest[keyPath: keyPath]
            },
            select: { option in
                $branding.editorUpdateCrest { $0[keyPath: keyPath] = option }
            },
            artwork: { option in
                BrowserSpaceCrestIcon(
                    branding: $branding.editorPreview {
                        $0.crest[keyPath: keyPath] = option
                    },
                    size: iconSize,
                    rasterizesLayers: false
                )
            }
        )
    }
}

#Preview("Branding Editor — Crest Option Gallery") {
    @Previewable @State var branding = BrowserSpaceBrandingPreviewFixture.crestBranding

    ScrollView {
        BrowserSpaceCrestOptionGallery(
            branding: $branding,
            options: BrowserSpaceCrestBackplate.allCases,
            keyPath: \.backplate,
            compact: false
        )
        .padding(CrestSpacing.large)
    }
    .frame(width: 620, height: 360)
}
