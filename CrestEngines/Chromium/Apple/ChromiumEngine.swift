#if CREST_CHROMIUM_HOST
    import CrestCoreABI
    import Foundation

    /// Chromium, the default engine. Its binding is the engine's own C++: the
    /// core hands it commands through the binding's function table, and the
    /// binding creates, loads and closes each page and reports what it does
    /// straight to the core. This hosts the pages' views and keeps the pages the
    /// platform acts on directly.
    @MainActor
    final class ChromiumEngine: NativeEngineBinding {
        // MARK: - Variables

        let integration = BrowserEngineRegistration.chromium
        let table: crest_engine_binding_t
        let fingerprint: [UInt8]
        /// The browser operations a page may ask for, such as the Space a
        /// Chrome Web Store listing installs into. Weak: the composition owns it.
        weak var hostCommands: (any BrowserEngineHostCommands)?
        private let host: any CrestChromiumEngineHost
        /// The page hosted for each page the core opened, while its owner keeps it.
        private var pages: [UUID: WeakNativePage] = [:]

        // MARK: - Initializers

        init(host: any CrestChromiumEngineHost, table: crest_engine_binding_t, fingerprint: [UInt8]) {
            self.host = host
            self.table = table
            self.fingerprint = fingerprint
        }

        // MARK: - Actions - Pages

        func host(_ page: CorePage) -> AnyObject {
            pages = pages.filter { $0.value.page != nil }
            let native = ChromiumNativePage(id: page.id, host: host, hostCommands: hostCommands)
            pages[page.id] = WeakNativePage(page: native)
            return ChromiumPageAdapter(native)
        }

        func icon(of pageID: UUID) -> Data? {
            host.icon(forPage: pageID.uuidString)
        }

        /// The live page the engine names with `id`, for requests that arrive
        /// with only a page identifier, such as a side panel's.
        func page(_ id: String) -> ChromiumNativePage? {
            UUID(uuidString: id).flatMap { pages[$0]?.page }
        }
    }

    /// A hosted page, held weakly so it goes with its owner.
    private struct WeakNativePage {
        weak var page: ChromiumNativePage?
    }

    /// The framework's entry point, which Chromium calls on its UI thread, the
    /// main thread, once it loads the framework: the Mac shell's host and the
    /// engine binding to register with the core the framework creates.
    @MainActor
    @_cdecl("crest_chromium_ui_start")
    func crestChromiumUIStart(
        _ host: any CrestChromiumEngineHost, _ binding: UnsafePointer<crest_engine_binding_t>,
        _ fingerprint: UnsafePointer<UInt8>, _ fingerprintLength: Int
    ) {
        let contract = Array(UnsafeBufferPointer(start: fingerprint, count: fingerprintLength))
        CrestChromiumRoot.start(host: host, binding: binding.pointee, fingerprint: contract)
    }
#endif
