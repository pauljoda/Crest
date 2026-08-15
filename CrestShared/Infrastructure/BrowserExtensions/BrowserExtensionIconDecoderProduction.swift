import CoreGraphics

enum BrowserExtensionIconDecoderProduction {
    static let shared = BrowserExtensionIconDecoder<CGImage>(
        decodingPort: BrowserExtensionIconImageIOAdapter()
    )
}
