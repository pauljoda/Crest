enum BrowserTabDragSessionLifecyclePolicy {
    /// iOS 27 finally exposes the native drag session's terminal phase to
    /// SwiftUI. It is the source-side completion signal that still fires when
    /// a drag is cancelled or released outside every DropDelegate.
    static let nativeCompletionRuntimeMajorVersion = 27

    static func usesNativeCompletion(runtimeMajorVersion: Int) -> Bool {
        runtimeMajorVersion >= nativeCompletionRuntimeMajorVersion
    }

    static func shouldEnd(
        for phase: BrowserTabDragSessionLifecyclePhase
    ) -> Bool {
        phase == .ended || phase == .dataTransferCompleted
    }
}
