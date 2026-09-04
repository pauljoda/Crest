import Foundation
import WebKit

/// Installs the page-world `chrome.runtime` alias and the relay behind it into
/// the extension web views Crest hosts itself — the side panel and offscreen
/// documents.
///
/// A browser tab owns its user content controller, so `BrowserPage` simply adds
/// its handlers and removes them when the page closes. An extension document
/// does not: WebKit hands out a *copy* of the extension controller's web view
/// configuration, and the copy carries the same `WKUserContentController`.
/// Two windows each showing the same extension's panel, or a panel and that
/// extension's offscreen document, therefore arrive at one controller — and
/// adding a script message handler under a name it already holds raises. This
/// type owns the installation for that controller instead: the first document
/// installs, the rest join, and the handlers are removed when the last one
/// closes.
@MainActor
enum BrowserExtensionHostedDocumentRuntimeBridge {
    /// One document's share of an installation. Releasing the last one removes
    /// the handlers.
    @MainActor
    struct Handle {
        fileprivate let controller: WKUserContentController

        func release() {
            BrowserExtensionHostedDocumentRuntimeBridge.release(
                controller: controller
            )
        }
    }

    private final class Installation {
        var owners = 0
        /// A `WKUserContentController` can add a user script but never remove
        /// one, so the alias is added at most once per controller and outlives
        /// the documents that asked for it. It is inert on its own: it looks
        /// for the relay's reply handler at document start and finds nothing
        /// once the last document has released it.
        var hasAliasScript = false
        var diagnostics: BrowserExtensionWebPageRuntimeDiagnosticsProxy?
        var relay: BrowserExtensionWebPageRuntimeRelay?
    }

    /// Keyed weakly: WebKit hands out a configuration copy per document, the
    /// copies share one controller, and an entry must not outlive the
    /// controller it describes.
    private static let installations =
        NSMapTable<WKUserContentController, Installation>.weakToStrongObjects()

    /// Adds the alias and the relay for `configuration`'s web view, or joins
    /// the installation the controller already carries. `nil` when the Space
    /// has no `externally_connectable` patterns at all, in which case no frame
    /// in this document could use either.
    static func install(
        for configuration: BrowserExtensionPageConfiguration,
        reportsDiagnostics: Bool,
        resolveTarget: @escaping BrowserExtensionWebPageRuntimeRelay.Resolve
    ) -> Handle? {
        guard !configuration.externallyConnectableMatchPatterns.isEmpty else {
            return nil
        }
        let controller =
            configuration.webViewConfiguration.userContentController
        let installation =
            installations.object(forKey: controller)
            ?? {
                let created = Installation()
                installations.setObject(created, forKey: controller)
                return created
            }()
        installation.owners += 1
        guard installation.owners == 1 else {
            return Handle(controller: controller)
        }
        let relay = BrowserExtensionWebPageRuntimeRelay(
            reportsDiagnostics: reportsDiagnostics,
            resolveTarget: resolveTarget
        )
        controller.addScriptMessageHandler(
            relay,
            contentWorld: BrowserExtensionWebPageRuntimeRelay.contentWorld,
            name: BrowserExtensionWebPageRuntimeRelay.messageHandlerName
        )
        installation.relay = relay
        if reportsDiagnostics {
            let diagnostics = BrowserExtensionWebPageRuntimeDiagnosticsProxy()
            controller.add(
                diagnostics,
                contentWorld: BrowserExtensionWebPageRuntimeBridge.contentWorld,
                name: BrowserExtensionWebPageRuntimeBridge
                    .diagnosticsHandlerName
            )
            installation.diagnostics = diagnostics
        }
        if !installation.hasAliasScript {
            BrowserExtensionWebPageRuntimeBridge.installScript(
                in: controller,
                matchPatterns: configuration.externallyConnectableMatchPatterns,
                reportsDiagnostics: reportsDiagnostics
            )
            installation.hasAliasScript = true
        }
        return Handle(controller: controller)
    }

    private static func release(controller: WKUserContentController) {
        guard let installation = installations.object(forKey: controller)
        else { return }
        installation.owners -= 1
        guard installation.owners <= 0 else { return }
        installation.owners = 0
        if installation.relay != nil {
            controller.removeScriptMessageHandler(
                forName: BrowserExtensionWebPageRuntimeRelay
                    .messageHandlerName,
                contentWorld: BrowserExtensionWebPageRuntimeRelay.contentWorld
            )
            installation.relay = nil
        }
        if installation.diagnostics != nil {
            controller.removeScriptMessageHandler(
                forName: BrowserExtensionWebPageRuntimeBridge
                    .diagnosticsHandlerName,
                contentWorld: BrowserExtensionWebPageRuntimeBridge.contentWorld
            )
            installation.diagnostics = nil
        }
    }

    /// The relay's view of one extension in `spaceID`, read from the pool.
    static func target(
        extensionID: String,
        in spaceID: SpaceID,
        pool: BrowserExtensionControllerPool
    ) -> BrowserExtensionWebPageRuntimeRelay.Target? {
        guard
            let context = pool.loadedContext(
                extensionID: extensionID,
                in: spaceID
            )
        else { return nil }
        return BrowserExtensionWebPageRuntimeRelay.Target(
            externallyConnectableMatchPatterns:
                BrowserExtensionExternallyConnectablePolicy.matchPatterns(
                    in: context.webExtension.manifest
                ),
            hasHostAccess: { [weak context] url in
                context?.hasAccess(to: url) ?? false
            },
            deliver: { [weak pool] messageJSON, sender in
                guard let pool else { return nil }
                return await pool.deliverExternalWebPageMessage(
                    messageJSON: messageJSON,
                    sender: sender,
                    to: extensionID,
                    in: spaceID
                )
            }
        )
    }
}
