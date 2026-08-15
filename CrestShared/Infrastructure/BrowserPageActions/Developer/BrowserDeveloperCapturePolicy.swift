import CoreGraphics
import Foundation

enum BrowserDeveloperCapturePolicy {
    private static let minimumSelectionLength: CGFloat = 12

    static func captureRect(
        from start: CGPoint,
        to end: CGPoint,
        in bounds: CGRect
    ) -> CGRect? {
        let proposed = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        let clipped = proposed.intersection(bounds)
        guard !clipped.isNull,
              clipped.width >= minimumSelectionLength,
              clipped.height >= minimumSelectionLength else {
            return nil
        }
        return clipped
    }

    static func pngFilename(title: String?, url: URL?) -> String {
        BrowserPageExportPolicy.imageFilename(title: title, url: url)
    }
}
