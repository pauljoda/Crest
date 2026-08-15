enum BrowserPlatformExtensionActions {
    @MainActor
    static func make(
        extensionControllerPool: BrowserExtensionControllerPool
    ) -> BrowserExtensionPlatformActions {
        BrowserExtensionPlatformActions { extensionID, spaceID in
            extensionControllerPool.openOptionsPage(
                extensionID: extensionID,
                in: spaceID
            )
        }
    }
}
