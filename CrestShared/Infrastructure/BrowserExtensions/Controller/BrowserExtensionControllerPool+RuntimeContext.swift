import Foundation
import WebKit

extension BrowserExtensionControllerPool {
    func controller(for space: BrowserSpace) -> WKWebExtensionController {
        runtimeContextController.controller(for: space)
    }

    func loadedContext(
        extensionID: String,
        in spaceID: SpaceID
    ) -> WKWebExtensionContext? {
        runtimeContextController.loadedContext(
            extensionID: extensionID,
            in: spaceID
        )
    }

    func webViewConfiguration(
        for extensionURL: URL,
        in spaceID: SpaceID
    ) -> WKWebViewConfiguration? {
        runtimeContextController.webViewConfiguration(
            for: extensionURL,
            in: spaceID
        )
    }

    func extensions(
        in spaceID: SpaceID
    ) -> [BrowserExtensionSummary] {
        persistenceController.extensions(
            in: spaceID,
            nativeMessagingCapability:
                runtimeContextController.nativeMessagingCapability
        )
    }
}
