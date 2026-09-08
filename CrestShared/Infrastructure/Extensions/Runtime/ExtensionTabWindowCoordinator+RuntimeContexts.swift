import Foundation
import WebKit

extension BrowserExtensionTabWindowCoordinator {
    /// Answers `chrome.runtime.getContexts` from the document registries Crest
    /// actually owns.
    ///
    /// `runtime` gates on no permission in Chrome and asks for none here, so
    /// this handler checks only that the context is authorized to use the
    /// internal broker at all — the same reasoning that lets
    /// `diagnostics.report` past the grant table. What it reports is narrow on
    /// purpose: the extension's own background, its Crest-hosted offscreen
    /// document, and every side-panel document Crest currently has loaded for
    /// it in the Space. `POPUP`, `TAB`, and `DEVELOPER_TOOLS` documents live
    /// inside WebKit's own page lifecycle, which publishes no enumeration
    /// Crest can read, so they are absent rather than guessed at.
    ///
    /// Tabs and windows leave here as a Space-relative tab index plus that
    /// tab's URL, exactly as the sidebar event channel reports them: WebKit
    /// owns the numeric IDs an extension sees, and the page-side wrapper
    /// resolves these back through `tabs.query`.
    func handleCapabilityBrokerRuntimeContexts(
        _ message: Any,
        applicationIdentifier: String?,
        controller: WKWebExtensionController,
        extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) -> Bool {
        guard
            applicationIdentifier
                == BrowserExtensionNativeMessagingApplication
                .capabilityBrokerIdentifier,
            let payload = message as? [String: Any],
            payload["api"] as? String == "runtime.getContexts"
        else {
            return false
        }
        guard
            let authorization = verifiedNativeMessagingAuthorizations[
                ObjectIdentifier(extensionContext)
            ],
            authorization.allowsInternalCapabilityBroker
        else {
            replyHandler(
                nil,
                BrowserExtensionNativeMessagingError.unverifiedExtension
            )
            return true
        }
        guard
            let (spaceID, _) = verifiedSpaceAndEntry(
                controller: controller,
                context: extensionContext
            )
        else {
            replyHandler(
                nil,
                BrowserExtensionCapabilityBrokerError.serviceFailure(
                    "Crest could not resolve this extension's Space."
                )
            )
            return true
        }
        let requestedTypes = Self.requestedContextTypes(payload["filter"])
        replyHandler(
            [
                "contexts": runtimeExtensionContexts(
                    for: extensionContext,
                    in: spaceID,
                    types: requestedTypes
                )
            ],
            nil
        )
        return true
    }

    /// The `contextTypes` the caller asked for, or nil for "every type".
    ///
    /// This is a shortcut, not the filter: the page-side wrapper applies the
    /// complete `ContextFilter` predicate after it has resolved the numeric
    /// tab and window IDs the other fields name. Honouring this one field here
    /// keeps a side-panel-only query from walking the sidebar registry's tab
    /// lookups for nothing.
    private static func requestedContextTypes(_ value: Any?) -> Set<String>? {
        guard let filter = value as? [String: Any],
            let types = filter["contextTypes"] as? [Any]
        else {
            return nil
        }
        return Set(types.compactMap { $0 as? String })
    }

    private func runtimeExtensionContexts(
        for extensionContext: WKWebExtensionContext,
        in spaceID: SpaceID,
        types: Set<String>?
    ) -> [[String: Any]] {
        let origin = Self.extensionOrigin(extensionContext.baseURL)
        var contexts: [[String: Any]] = []

        func includes(_ type: String) -> Bool {
            types?.contains(type) ?? true
        }

        if includes("BACKGROUND"),
            extensionContext.webExtension.hasBackgroundContent
        {
            // The page-side wrapper decides whether a background context
            // carries a `documentUrl`, because only the extension's own
            // declared manifest says whether its background is a worker or a
            // document — Crest's hosting choice must not leak through here.
            contexts.append(
                Self.context(
                    type: "BACKGROUND",
                    contextID: extensionContext.uniqueIdentifier,
                    origin: origin
                )
            )
        }

        if includes("OFFSCREEN_DOCUMENT"),
            let document = pageProvider?.extensionOffscreenDocument(
                extensionBaseURL: extensionContext.baseURL,
                in: spaceID
            )
        {
            contexts.append(
                Self.context(
                    type: "OFFSCREEN_DOCUMENT",
                    contextID: document.contextID,
                    origin: origin,
                    documentURL: document.url
                )
            )
        }

        guard includes("SIDE_PANEL") else { return contexts }
        let space = currentState?.space(spaceID)
        for document in pageProvider?.extensionSidebarDocuments(
            extensionBaseURL: extensionContext.baseURL,
            in: spaceID
        ) ?? [] {
            var context = Self.context(
                type: "SIDE_PANEL",
                contextID: document.contextID,
                origin: origin,
                documentURL: document.url
            )
            context["windowKind"] = "primary"
            if let tabID = document.tabID {
                // A panel scoped to a tab the session no longer has is still
                // an open document; it simply has no tab left to name.
                if let tab = space?.tab(tabID) {
                    context["tabIndex"] = tab.index
                    context["tabURL"] = tab.url?.absoluteString
                }
            }
            contexts.append(context)
        }
        return contexts
    }

    private static func context(
        type: String,
        contextID: String,
        origin: String?,
        documentURL: URL? = nil
    ) -> [String: Any] {
        var context: [String: Any] = [
            "contextType": type,
            "contextId": contextID,
            "frameId": 0,
            // Crest hosts no extension document in a private Space: extension
            // controllers are per-Space and a private Space loads none.
            "incognito": false,
        ]
        if let documentURL {
            context["documentUrl"] = documentURL.absoluteString
        }
        if let origin {
            context["documentOrigin"] = origin
        }
        return context
    }

    /// The extension's origin, as `documentOrigin` reports it: scheme, host,
    /// and non-default port, with no path.
    private static func extensionOrigin(_ baseURL: URL) -> String? {
        guard
            var components = URLComponents(
                url: baseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string
    }
}
