#if CREST_CHROMIUM_HOST
extension BrowserEngineRegistration {
    /// Selected by the process composition, never by synced Space records.
    static var current: BrowserAdapterRegistration { chromium }
}
#endif
