/// Reader Mode's isolated-world script, served from `CrestCore` so every
/// platform and engine runs the exact same article extractor and renderer.
enum BrowserReaderModeJavaScriptBridge {
    // MARK: - Static Variables

    static let source: String = ContentBridge.readerMode.script().source
}
