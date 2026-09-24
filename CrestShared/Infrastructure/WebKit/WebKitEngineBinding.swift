import Foundation

/// WebKit's binding, on the Mac and on iPhone and iPad. For now the page's
/// owner builds the WebKit page with the factory it already had, because that
/// factory carries the owner's configuration, content rules and website data
/// stores; the binding runs it when the core asks WebKit to create the page,
/// and loads an address through the owner's own load, which prepares the
/// page for it. The owner tears the web view down when it releases the page,
/// so closing only tells the core the page is gone.
@MainActor
final class WebKitEngineBinding: EngineBinding {
    // MARK: - Variables

    let integration = BrowserEngineRegistration.webKit
    private weak var engines: Engines?

    // MARK: - Actions - Binding

    func attach(to engines: Engines) {
        self.engines = engines
    }

    func run(_ command: EngineCommand) {
        guard let engines else { return }
        switch command {
        case .createPage(let creation):
            guard let request = engines.request(creation.pageID), let built = request.makeWebKitPage(request.page)
            else {
                engines.report(PageCreationFailed(pageID: creation.pageID), from: self)
                return
            }
            request.built = built
            engines.report(PageCreated(pageID: creation.pageID), from: self)
        case .loadPage(let loading):
            guard let url = URL(string: loading.url) else { return }
            (engines.page(loading.pageID) ?? engines.request(loading.pageID)?.page)?.appLoad?(url)
        case .closePage(let closing):
            engines.report(PageClosed(pageID: closing.pageID), from: self)
        }
    }
}
