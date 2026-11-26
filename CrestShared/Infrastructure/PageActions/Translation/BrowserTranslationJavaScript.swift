/// Whole-page translation's isolated-world script, served from `CrestCore` so
/// every platform and engine samples and patches the DOM identically.
enum BrowserTranslationJavaScript {
    // MARK: - Static Variables

    static let source: String = ContentBridge.translation.script().source
}
