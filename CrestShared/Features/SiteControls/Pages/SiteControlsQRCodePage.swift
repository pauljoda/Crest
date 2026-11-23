import CoreImage.CIFilterBuiltins
import SwiftUI

/// The page's address as a code another device's camera reads. It is the
/// address Crest hands out, without the trackers Super Copy removes.
struct SiteControlsQRCodePage: View {
    let model: SiteControlsModel

    @Environment(\.siteControlsMetrics) private var metrics

    var body: some View {
        VStack(spacing: CrestSpacing.medium) {
            if let link = model.page.linkToCopy, let image = Self.code(for: link.url.absoluteString) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(CrestSpacing.medium)
                    .background(Color.white, in: .rect(cornerRadius: CrestRadius.control))
                    .accessibilityLabel(Text("QR code for \(model.host ?? link.url.absoluteString)"))
                    .accessibilityIdentifier("site-control-qr-code")
                Button("Copy Link") { model.platform.run(.copyPageLink) }
                    .buttonStyle(SiteControlsTextButtonStyle())
            } else {
                Text("This page has no address to share.")
                    .font(metrics.rowFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, CrestSpacing.small)
    }

    /// `text` drawn as a QR code, one pixel a module, for the view to scale.
    private static func code(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}
