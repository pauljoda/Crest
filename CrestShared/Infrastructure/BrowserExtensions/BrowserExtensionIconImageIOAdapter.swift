import CoreGraphics
import Foundation
import ImageIO

struct BrowserExtensionIconImageIOAdapter: BrowserExtensionIconDecoding {
    func decode(
        _ data: Data,
        maximumPixelSize: Int
    ) async -> CGImage? {
        guard !data.isEmpty,
            data.count <= BrowserExtensionIconPayload.maximumEncodedByteCount,
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetStatus(source) != .statusInvalidData,
            CGImageSourceGetCount(source) > 0
        else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        )
    }
}
