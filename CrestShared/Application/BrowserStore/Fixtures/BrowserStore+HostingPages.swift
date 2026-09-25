#if DEBUG || CREST_PERFORMANCE_HARNESS
    import Foundation

    extension CrestCore {
        /// A memory-only core that hosts pages the way the app composes one, for
        /// tests: WebKit is registered as its default engine.
        static func hostingPages() -> CrestCore {
            let core = CrestCore()
            core.engines.register(WebKitEngineBinding(), isDefault: true)
            return core
        }
    }

    extension BrowserStore {
        /// A window that hosts pages the way the app composes one, for tests: a
        /// family holding `session` on a core that hosts pages,
        /// and a window open over it that shows `spaceID` and `tabs` as
        /// `init(session:showing:tabs:)` does. A page pool or store over this
        /// window opens every page through that core, so a page can only live
        /// in one of the session's Spaces. Pass `core` to put another workspace
        /// on a core that already hosts one, as private and temporary windows
        /// share the app's core.
        static func hostingPages(
            _ session: BrowserSession = .preview,
            showing spaceID: SpaceID? = nil,
            tabs: [SpaceID: TabID] = [:],
            browsingMode: BrowserBrowsingMode = .standard,
            core: CrestCore = .hostingPages()
        ) -> BrowserStore {
            BrowserStore(session: session, showing: spaceID, tabs: tabs, browsingMode: browsingMode, core: core)
        }
    }
#endif
