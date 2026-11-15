import SwiftUI

/// Where a link the pointer rests on leads, at the bottom corner of the page
/// on Crest's flyout surface.
struct BrowserLinkHoverPreview: View {
    let hover: BrowserLinkHoverController

    var body: some View {
        GeometryReader { geometry in
            if let destination = hover.destination {
                Text(verbatim: destination.text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(hover.isExpanded ? 4 : 1)
                    .truncationMode(hover.isExpanded ? .tail : .middle)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .fixedSize(horizontal: false, vertical: true)
                    .crestFloatingFlyoutStyle(in: .rect(cornerRadius: 10))
                    .frame(maxWidth: min(560, max(0, geometry.size.width - 24)), alignment: .leading)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel("Link destination")
                    .accessibilityValue(Text(verbatim: destination.text))
                    .accessibilityIdentifier("browser-link-hover-preview")
            }
        }
        .allowsHitTesting(false)
    }
}
