import CoreGraphics

enum BrowserExtensionIconDecoderProduction {
    static let shared = BrowserExtensionIconDecoder<CGImage>(
        decodingPort: BrowserExtensionIconImageIOAdapter()
    )
}

extension BrowserExtensionIconDecoder where DecodedIcon == CGImage {
    static var shared: BrowserExtensionIconDecoder<CGImage> {
        BrowserExtensionIconDecoderProduction.shared
    }
}
