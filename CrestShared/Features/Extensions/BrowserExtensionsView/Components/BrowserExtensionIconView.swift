import CoreGraphics
import SwiftUI

struct BrowserExtensionIconView: View {
    private let request: BrowserExtensionIconRequest
    private let size: CGFloat
    private let decoder: BrowserExtensionIconDecoder<CGImage>

    @State private var renderState = BrowserExtensionIconRenderState<CGImage>()

    init(
        extensionID: String?,
        spaceID: SpaceID,
        payload: BrowserExtensionIconPayload?,
        size: CGFloat = BrowserExtensionsMetrics.extensionIconSize,
        decoder: BrowserExtensionIconDecoder<CGImage> = .shared
    ) {
        request = BrowserExtensionIconRequest(
            extensionID: extensionID,
            spaceID: spaceID,
            payload: payload,
            maximumPixelSize:
                BrowserExtensionsMetrics
                .maximumDecodedPixelSize(for: size)
        )
        self.size = size
        self.decoder = decoder
    }

    var body: some View {
        Group {
            if let renderedIcon = renderState.icon(for: request.identity) {
                Image(
                    decorative: renderedIcon,
                    scale: BrowserExtensionsMetrics.renderedExtensionIconScale
                )
                .resizable()
            } else {
                fallback
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
        .clipShape(
            .rect(
                cornerRadius: size
                    * BrowserExtensionsMetrics.extensionIconCornerRadiusRatio,
                style: .continuous
            )
        )
        .task(id: request.identity) {
            await loadRenderedIcon()
        }
    }

    private var fallback: some View {
        Image(systemName: "puzzlepiece.extension.fill")
            .resizable()
            .scaledToFit()
            .padding(
                size
                    * BrowserExtensionsMetrics.extensionIconFallbackPaddingRatio
            )
            .foregroundStyle(.secondary)
    }

    private func loadRenderedIcon() async {
        let identity = request.identity
        renderState.clear()
        guard request.payload != nil else { return }
        let icon = await decoder.icon(for: request)
        guard !Task.isCancelled else { return }
        renderState.store(icon, for: identity)
    }
}
