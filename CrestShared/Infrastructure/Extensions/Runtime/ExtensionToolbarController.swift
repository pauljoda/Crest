@MainActor
final class BrowserExtensionToolbarController {
    let persistence: BrowserExtensionPersistenceController
    let runtime: BrowserExtensionRuntimeContextController
    let tabWindowCoordinator: BrowserExtensionTabWindowCoordinator
    let webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry

    init(
        persistence: BrowserExtensionPersistenceController,
        runtime: BrowserExtensionRuntimeContextController,
        tabWindowCoordinator: BrowserExtensionTabWindowCoordinator,
        webpageMenuRegistry: BrowserExtensionWebpageMenuRegistry
    ) {
        self.persistence = persistence
        self.runtime = runtime
        self.tabWindowCoordinator = tabWindowCoordinator
        self.webpageMenuRegistry = webpageMenuRegistry
    }

    func setPinned(
        _ pinned: Bool,
        extensionID: String,
        in spaceID: SpaceID
    ) -> Bool {
        guard
            persistence.installation(
                extensionID: extensionID,
                in: spaceID
            ) != nil
        else {
            return false
        }
        persistence.setPinned(
            pinned,
            extensionID: extensionID,
            in: spaceID
        )
        guard
            let installation = persistence.installation(
                extensionID: extensionID,
                in: spaceID
            )
        else {
            return false
        }
        let summary: BrowserExtensionSummary
        if let context = runtime.loadedContext(
            extensionID: extensionID,
            in: spaceID
        ) {
            summary = runtime.summary(
                for: context,
                installation: installation
            )
        } else {
            summary = persistence.summary(
                for: installation,
                nativeMessagingCapability: runtime.nativeMessagingCapability
            )
        }
        persistence.updateSummary(summary, in: spaceID)
        return true
    }
}
