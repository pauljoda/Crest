import CoreGraphics

/// Native input feeds shared movement and release handling.
enum BrowserSidebarReorderLiftPhase {
    enum PreviewOwner {
        case application
        case nativeSession
    }

    case moved(startLocation: CGPoint, location: CGPoint)
    case released(previewOwner: PreviewOwner)
}
