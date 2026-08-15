import CoreGraphics

enum BrowserTabDragVisualPolicy {
    /// SwiftUI owns the native lift preview on mobile. Keep Crest's persistent
    /// source-row treatment only where the source also receives a guaranteed
    /// terminal callback; otherwise a context-menu long press can leave the
    /// row dimmed after the gesture has already ended.
    static func usesPersistentSourceStyle(
        isDragging: Bool,
        hasReliableTerminalLifecycle: Bool
    ) -> Bool {
        isDragging && hasReliableTerminalLifecycle
    }

    static func sourceScale(isDragging: Bool) -> CGFloat {
        isDragging ? 1.04 : 1
    }

    static func sourceOpacity(isDragging: Bool) -> Double {
        isDragging ? 0.42 : 1
    }

    static func sourceShadowRadius(isDragging: Bool) -> CGFloat {
        isDragging ? 10 : 0
    }

    static func sourceShadowYOffset(isDragging: Bool) -> CGFloat {
        isDragging ? 5 : 0
    }
}
