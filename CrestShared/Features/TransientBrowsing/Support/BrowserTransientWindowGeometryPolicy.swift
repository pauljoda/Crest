import CoreGraphics

enum BrowserTransientWindowGeometryPolicy {
    static let contentFraction: CGFloat = 0.8

    static func contentSize(in containerSize: CGSize) -> CGSize {
        CGSize(
            width: containerSize.width * contentFraction,
            height: containerSize.height * contentFraction
        )
    }

    static func centeredContentFrame(in containerFrame: CGRect) -> CGRect {
        let size = contentSize(in: containerFrame.size)
        return CGRect(
            x: containerFrame.midX - (size.width / 2),
            y: containerFrame.midY - (size.height / 2),
            width: size.width,
            height: size.height
        )
    }
}
