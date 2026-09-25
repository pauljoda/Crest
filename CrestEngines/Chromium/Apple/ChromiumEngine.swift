#if CREST_CHROMIUM_HOST
    import CrestCoreABI
    import Foundation

    /// Chromium, the default engine. Its binding is the engine's own C++: the
    /// core hands it commands through the binding's function table, and the
    /// binding creates, loads and closes each page and reports what it does
    /// straight to the core. This hosts the pages' views, and its pages ask
    /// the binding for their view work directly.
    @MainActor
    final class ChromiumEngine: NativeEngineBinding {
        // MARK: - Variables

        let integration = BrowserEngineRegistration.chromium
        let table: crest_engine_binding_t
        let fingerprint: [UInt8]
        /// The browser operations a page may ask for, such as the Space a
        /// Chrome Web Store listing installs into. Weak: the composition owns it.
        weak var hostCommands: (any BrowserEngineHostCommands)?
        /// The Mac shell, for what only AppKit does.
        let host: any CrestChromiumEngineHost
        /// The pages' direct path to the binding, which hears the binding's
        /// presentations from its first request on.
        private(set) lazy var pages = NativeEnginePages(table: pagesTable) { [weak self] presentation in
            self?.present(presentation)
        }
        private let pagesTable: crest_engine_pages_t
        /// Each page this hosts, while its owner keeps it.
        private var hosted: [UUID: WeakNativePage] = [:]

        // MARK: - Initializers

        init(
            host: any CrestChromiumEngineHost, table: crest_engine_binding_t, fingerprint: [UInt8],
            pages: crest_engine_pages_t
        ) {
            self.host = host
            self.table = table
            self.fingerprint = fingerprint
            pagesTable = pages
        }

        // MARK: - Actions - Pages

        func host(_ page: CorePage) -> AnyObject {
            let native = ChromiumNativePage(id: page.id, engine: self)
            hold(native)
            return ChromiumPageAdapter(native)
        }

        /// One of the engine's own pages that Settings shows in `profileID`,
        /// which no tab owns and the core never hears of.
        func standalonePage(in profileID: UUID) -> ChromiumNativePage {
            let native = ChromiumNativePage(standaloneIn: profileID, engine: self)
            hold(native)
            return native
        }

        func icon(of pageID: UUID) -> Data? {
            pages.request(PageIcon(pageID: pageID)).image
        }

        /// The live page the engine names with `id`, for requests that arrive
        /// with only a page identifier, such as a side panel's.
        func page(_ id: String) -> ChromiumNativePage? {
            UUID(uuidString: id).flatMap { hosted[$0]?.page }
        }

        private func hold(_ native: ChromiumNativePage) {
            hosted = hosted.filter { $0.value.page != nil }
            hosted[native.pageID] = WeakNativePage(page: native)
        }

        /// Hands a presentation to the page it names; one for a page that is
        /// gone changes nothing.
        private func present(_ presentation: EnginePresentation) {
            switch presentation {
            case .findFinished(let finished): hosted[finished.pageID]?.page?.receive(finished)
            case .pageCaptured(let captured): hosted[captured.pageID]?.page?.receive(captured)
            case .pageExported(let exported): hosted[exported.pageID]?.page?.receive(exported)
            }
        }
    }

    /// A hosted page, held weakly so it goes with its owner.
    private struct WeakNativePage {
        weak var page: ChromiumNativePage?
    }

    /// The framework's entry point, which Chromium calls on its UI thread, the
    /// main thread, once it loads the framework: the Mac shell's host, the
    /// engine binding to register with the core the framework creates, and the
    /// pages' direct path to it.
    @MainActor
    @_cdecl("crest_chromium_ui_start")
    func crestChromiumUIStart(
        _ host: any CrestChromiumEngineHost, _ binding: UnsafePointer<crest_engine_binding_t>,
        _ fingerprint: UnsafePointer<UInt8>, _ fingerprintLength: Int, _ pages: UnsafePointer<crest_engine_pages_t>
    ) {
        let contract = Array(UnsafeBufferPointer(start: fingerprint, count: fingerprintLength))
        CrestChromiumRoot.start(host: host, binding: binding.pointee, fingerprint: contract, pages: pages.pointee)
    }
#endif
