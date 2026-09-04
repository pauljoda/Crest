import AppKit

extension BrowserPagePool {
    func extensionSidebarIcon(for panel: BrowserExtensionSidebarPanel) -> NSImage? {
        guard let url = panel.documentURL,
            let configuration = extensionControllerPool.extensionPageConfiguration(for: url, in: panel.spaceID)
        else { return nil }
        if case .packagePath(let path) = panel.icon,
            let resource = BrowserExtensionSidebarResourcePolicy.documentURL(
                path: path, baseURL: configuration.baseURL),
            let summary = extensionControllerPool.extensions(in: panel.spaceID).first(where: {
                BrowserExtensionServiceClientID.scoped(extensionID: $0.id, spaceID: panel.spaceID) == panel.clientID
            }),
            let installation = extensionControllerPool.persistenceController.installation(
                extensionID: summary.id, in: panel.spaceID),
            let root = try? extensionControllerPool.persistenceController.resourceURL(
                packageName: installation.packageName, in: panel.spaceID)
        {
            let normalizedRoot = root.resolvingSymlinksInPath().standardizedFileURL
            let file = root.appending(path: String(resource.path.drop(while: { $0 == "/" }))).resolvingSymlinksInPath()
                .standardizedFileURL
            if file.path.hasPrefix(normalizedRoot.path + "/"), let image = NSImage(contentsOf: file) { return image }
        }
        return configuration.context.action(for: nil)?.icon(for: CGSize(width: 16, height: 16))
            ?? configuration.context.webExtension.icon(for: CGSize(width: 16, height: 16))
    }

    func extensionSidebarDocument(for panel: BrowserExtensionSidebarPanel, in window: BrowserWindowID)
        -> BrowserExtensionSidebarDocument?
    {
        guard let url = panel.documentURL,
            let configuration = extensionControllerPool.extensionPageConfiguration(for: url, in: panel.spaceID),
            BrowserExtensionSidebarResourcePolicy.documentURL(path: panel.path, baseURL: configuration.baseURL) == url
        else { return nil }
        let key = BrowserExtensionSidebarKey(
            windowID: window, spaceID: panel.spaceID, extensionBaseURL: configuration.baseURL)
        if let existing = extensionSidebarDocuments[key], existing.url == url,
            existing.tabID == panel.tabID, existing.webView != nil
        {
            return existing
        }
        closeExtensionSidebars(inWindow: window)
        let document = BrowserExtensionSidebarDocument(url: url, tabID: panel.tabID, configuration: configuration) {
            [weak self] url in
            self?.openExtensionSidebarLink(url)
        }
        extensionSidebarDocuments[key] = document
        return document
    }

    func closeExtensionSidebars(
        inWindow window: BrowserWindowID? = nil, inSpace space: SpaceID? = nil, baseURL: URL? = nil
    ) {
        let keys = extensionSidebarDocuments.keys.filter {
            (window == nil || $0.windowID == window) && (space == nil || $0.spaceID == space)
                && (baseURL == nil || $0.extensionBaseURL == baseURL)
        }
        for key in keys { extensionSidebarDocuments.removeValue(forKey: key)?.close() }
    }

    func closeExtensionSidebars(extensionBaseURL: URL, in spaceID: SpaceID) {
        closeExtensionSidebars(inSpace: spaceID, baseURL: extensionBaseURL)
    }
}
