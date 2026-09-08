import Foundation
import ImageIO

struct BrowserExtensionIconEncodedDataValidator: Sendable {
    func containsCompleteImage(_ data: Data) -> Bool {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ),
            CGImageSourceGetStatus(source) == .statusComplete,
            CGImageSourceGetCount(source) > 0,
            CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                nil
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.intValue > 0,
            height.intValue > 0
        else {
            return false
        }
        return true
    }
}
