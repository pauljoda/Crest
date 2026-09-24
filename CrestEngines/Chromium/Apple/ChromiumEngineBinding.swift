#if CREST_CHROMIUM_HOST
    import Foundation

    /// Chromium's binding. It builds each page's Chromium page under the
    /// identity the core gave the page, keeps it until the core asks it to close
    /// it or the engine loses it, and reports what the engine does with it. The
    /// page's owner lets its host go when it releases the page, and closing
    /// makes sure of it.
    @MainActor
    final class ChromiumEngineBinding: EngineBinding {
        // MARK: - Variables

        let integration = BrowserEngineRegistration.chromium
        /// The browser operations a page may ask for, such as the Space a
        /// Chrome Web Store listing installs into. Weak: the composition owns it.
        weak var hostCommands: (any BrowserEngineHostCommands)?
        private weak var engines: Engines?
        /// The engine's pages by the core's identity, until each closes.
        private var pages: [UUID: ChromiumNativePage] = [:]

        // MARK: - Actions - Binding

        func attach(to engines: Engines) {
            self.engines = engines
        }

        func run(_ command: EngineCommand) {
            switch command {
            case .createPage(let creation):
                guard let request = engines?.request(creation.pageID) else {
                    report(PageCreationFailed(pageID: creation.pageID))
                    return
                }
                let page = ChromiumNativePage(
                    id: creation.pageID, profileID: creation.profileID, isPrivateBrowsing: creation.isPrivate,
                    hostCommands: hostCommands, binding: self)
                pages[creation.pageID] = page
                request.built = ChromiumPageAdapter(page)
            case .closePage(let closing):
                pages.removeValue(forKey: closing.pageID)?.dispose()
                report(PageClosed(pageID: closing.pageID))
            }
        }

        // MARK: - Actions - Pages

        /// The live page the engine names with `id`, for requests that arrive
        /// with only a page identifier, such as a side panel's.
        func page(_ id: String) -> ChromiumNativePage? {
            UUID(uuidString: id).flatMap { pages[$0] }
        }

        /// The engine created `page`, which is now live.
        func pageCreated(_ page: ChromiumNativePage) {
            report(PageCreated(pageID: page.pageID))
        }

        /// The engine could not create `page`, so nothing is left to close. Its
        /// host lets it go when the page's owner releases it.
        func pageCreationFailed(_ page: ChromiumNativePage) {
            guard pages.removeValue(forKey: page.pageID) != nil else { return }
            report(PageCreationFailed(pageID: page.pageID))
        }

        /// The engine lost `page` on its own, as `window.close()` makes it.
        /// The engine is still inside its own teardown here, so the page is let
        /// go when its owner releases it.
        func pageClosed(_ page: ChromiumNativePage) {
            guard pages.removeValue(forKey: page.pageID) != nil else { return }
            report(PageClosed(pageID: page.pageID))
        }

        /// Reports what the engine saw one of its pages do. `icon` is the image
        /// a `PageIconChanged` names, which waits for the tab that adopts it.
        func pageReported(_ event: some EngineEvent, icon: (page: UUID, data: Data)?) {
            engines?.report(event, from: self, icon: icon)
        }

        private func report(_ event: some EngineEvent) {
            engines?.report(event, from: self)
        }
    }
#endif
