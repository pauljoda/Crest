import Foundation
import WebKit

@MainActor
final class BrowserExtensionTabAdapter: NSObject, WKWebExtensionTab {
    let tabID: TabID
    let spaceID: SpaceID
    private weak var coordinator: BrowserExtensionTabWindowCoordinator?

    init(
        tabID: TabID,
        spaceID: SpaceID,
        coordinator: BrowserExtensionTabWindowCoordinator
    ) {
        self.tabID = tabID
        self.spaceID = spaceID
        self.coordinator = coordinator
    }

    func window(
        for context: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard
            coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            return nil
        }
        return coordinator?.window(for: tabID, in: spaceID)
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        coordinator?.state(for: tabID, in: spaceID, context: context)?.index
            ?? NSNotFound
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        coordinator?.webView(for: tabID, in: spaceID, context: context)
    }

    func title(for context: WKWebExtensionContext) -> String? {
        guard let coordinator,
            let state = coordinator.state(
                for: tabID,
                in: spaceID,
                context: context
            ),
            coordinator.canRevealSensitiveProperties(
                of: self,
                state: state,
                context: context
            )
        else {
            return nil
        }
        return state.title
    }

    func url(for context: WKWebExtensionContext) -> URL? {
        guard let coordinator,
            let state = coordinator.state(
                for: tabID,
                in: spaceID,
                context: context
            ),
            coordinator.canRevealSensitiveProperties(
                of: self,
                state: state,
                context: context
            )
        else {
            return nil
        }
        return state.url
    }

    /// Chrome's `pinned` is the pinned strip and nothing else. Crest also has
    /// saved tabs, which are neither pinned nor current, and reporting them as
    /// pinned made every saved tab look like a member of a strip it is not in.
    func isPinned(for context: WKWebExtensionContext) -> Bool {
        guard
            let placement = coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            )?.placement
        else {
            return false
        }
        return placement == .pinned
    }

    /// `tabs.update({pinned: true})` on a saved tab pins it, because Crest's
    /// own Pin Tab action is offered for saved tabs too. `pinned: false` only
    /// acts on a tab that is actually in the pinned strip: a saved tab already
    /// reports `pinned: false`, and pulling it out of the saved list would be
    /// a move no caller asked for.
    func setPinned(
        _ pinned: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        coordinator?.setPinned(
            pinned,
            tabID: tabID,
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }

    func pendingURL(for context: WKWebExtensionContext) -> URL? {
        guard let webView = webView(for: context), webView.isLoading else {
            return nil
        }
        return webView.url
    }

    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool {
        webView(for: context)?.isLoading != true
    }

    func size(for context: WKWebExtensionContext) -> CGSize {
        webView(for: context)?.bounds.size ?? .zero
    }

    func isReaderModeAvailable(for context: WKWebExtensionContext) -> Bool {
        readerModeState(for: context).isAvailable
    }

    func isReaderModeActive(for context: WKWebExtensionContext) -> Bool {
        readerModeState(for: context).isActive
    }

    func setReaderModeActive(
        _ active: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let coordinator,
            coordinator.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        coordinator.setReaderModeActive(
            active,
            tabID: tabID,
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }

    func detectWebpageLocale(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Locale?, Error?) -> Void
    ) {
        guard let webView = webView(for: context) else {
            completionHandler(nil, coordinator?.adapterError(.tabUnavailable))
            return
        }
        webView.evaluateJavaScript(
            "document.documentElement.lang"
        ) { value, _ in
            // A page that declares no language is not an error: the WebExtension
            // contract asks for a nil locale in that case.
            let tag = (value as? String)?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard let tag, !tag.isEmpty else {
                completionHandler(nil, nil)
                return
            }
            completionHandler(Locale(identifier: tag), nil)
        }
    }

    func takeSnapshot(
        using configuration: WKSnapshotConfiguration,
        for context: WKWebExtensionContext,
        completionHandler:
            @escaping (BrowserExtensionSnapshotImage?, Error?) ->
            Void
    ) {
        guard let webView = webView(for: context) else {
            completionHandler(nil, coordinator?.adapterError(.tabUnavailable))
            return
        }
        webView.takeSnapshot(with: configuration) { image, error in
            completionHandler(image, error)
        }
    }

    private func readerModeState(
        for context: WKWebExtensionContext
    ) -> BrowserReaderModeState {
        guard let coordinator,
            coordinator.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            return .unavailable
        }
        return coordinator.readerModeState(for: tabID, in: spaceID)
    }

    func zoomFactor(for context: WKWebExtensionContext) -> Double {
        Double(webView(for: context)?.pageZoom ?? 1)
    }

    func setZoomFactor(
        _ zoomFactor: Double,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: context) else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        webView.pageZoom = CGFloat(zoomFactor)
        completionHandler(nil)
    }

    func loadURL(
        _ url: URL,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        coordinator?.load(
            url,
            tabID: tabID,
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }

    func reload(
        fromOrigin: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: context) else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
        completionHandler(nil)
    }

    func goBack(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: context), webView.canGoBack else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        webView.goBack()
        completionHandler(nil)
    }

    func goForward(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let webView = webView(for: context), webView.canGoForward else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        webView.goForward()
        completionHandler(nil)
    }

    func activate(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        coordinator?.activate(
            tabID: tabID,
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }

    func isSelected(for context: WKWebExtensionContext) -> Bool {
        coordinator?.state(
            for: tabID,
            in: spaceID,
            context: context
        )?.isSelected == true
    }

    func setSelected(
        _ selected: Bool,
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard selected else {
            completionHandler(nil)
            return
        }
        activate(for: context, completionHandler: completionHandler)
    }

    func duplicate(
        using configuration: WKWebExtension.TabConfiguration,
        for context: WKWebExtensionContext,
        completionHandler: @escaping ((any WKWebExtensionTab)?, Error?) -> Void
    ) {
        guard
            coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            completionHandler(
                nil,
                coordinator?.adapterError(.tabUnavailable)
            )
            return
        }
        coordinator?.duplicate(
            tabID: tabID,
            spaceID: spaceID,
            configuration: configuration,
            completionHandler: completionHandler
        )
    }

    func close(
        for context: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard
            coordinator?.state(
                for: tabID,
                in: spaceID,
                context: context
            ) != nil
        else {
            completionHandler(coordinator?.adapterError(.tabUnavailable))
            return
        }
        coordinator?.close(
            tabID: tabID,
            spaceID: spaceID,
            completionHandler: completionHandler
        )
    }
}
