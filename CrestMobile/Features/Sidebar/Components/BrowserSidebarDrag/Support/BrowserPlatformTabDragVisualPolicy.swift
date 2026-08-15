enum BrowserPlatformTabDragVisualPolicy {
    static var hasReliableTerminalLifecycle: Bool {
        #if compiler(>=6.4)
            if #available(iOS 27.0, *) {
                true
            } else {
                false
            }
        #else
            false
        #endif
    }
}
