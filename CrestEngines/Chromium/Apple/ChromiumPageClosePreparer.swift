#if CREST_CHROMIUM_HOST
@MainActor
final class ChromiumPageClosePreparer: BrowserPageClosePreparing {
    private let host: any CrestChromiumEngineHost

    init(host: any CrestChromiumEngineHost) { self.host = host }

    func prepareToClose(_ pages: [any BrowserPageEngine], completion: @escaping @MainActor (Bool) -> Void) {
        let chromium = pages.compactMap { $0 as? ChromiumNativePage }
        guard chromium.count == pages.count else { completion(false); return }
        host.prepareToClose(pages: chromium.map(\.id), windows: []) { allowed in
            MainActor.assumeIsolated { completion(allowed) }
        }
    }
}
#endif
