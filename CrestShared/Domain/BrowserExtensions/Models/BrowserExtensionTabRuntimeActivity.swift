/// Live page state a `BrowserSession` cannot carry, resolved per tab while a
/// session snapshot is projected for extensions. A tab with no resident page
/// reports the settled values.
struct BrowserExtensionTabRuntimeActivity: Equatable, Sendable {
    static let settled = BrowserExtensionTabRuntimeActivity()

    let isLoadingComplete: Bool
    let isReaderModeActive: Bool

    init(
        isLoadingComplete: Bool = true,
        isReaderModeActive: Bool = false
    ) {
        self.isLoadingComplete = isLoadingComplete
        self.isReaderModeActive = isReaderModeActive
    }
}
