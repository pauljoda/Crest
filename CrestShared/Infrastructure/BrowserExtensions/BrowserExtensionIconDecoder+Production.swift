import CoreGraphics

extension BrowserExtensionIconDecoder where DecodedIcon == CGImage {
    static var shared: BrowserExtensionIconDecoder<CGImage> {
        BrowserExtensionIconDecoderProduction.shared
    }
}
