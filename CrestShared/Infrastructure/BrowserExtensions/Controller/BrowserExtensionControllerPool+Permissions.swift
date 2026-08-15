extension BrowserExtensionControllerPool {
    func permissionDecision(
        for permission: String,
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionAccessDecision {
        permissionController.permissionDecision(
            for: permission,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func hostDecision(
        for hostPattern: String,
        extensionID: String,
        in spaceID: SpaceID
    ) -> BrowserExtensionAccessDecision {
        permissionController.hostDecision(
            for: hostPattern,
            extensionID: extensionID,
            in: spaceID
        )
    }

    func setPermissionDecision(
        _ decision: BrowserExtensionAccessDecision,
        for permission: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        permissionController.setPermissionDecision(
            decision,
            for: permission,
            extensionID: extensionID,
            in: spaceID,
            context: loadedContext(
                extensionID: extensionID,
                in: spaceID
            ),
            nativeMessagingCapability:
                runtimeContextController.nativeMessagingCapability
        )
    }

    func setHostDecision(
        _ decision: BrowserExtensionAccessDecision,
        for hostPattern: String,
        extensionID: String,
        in spaceID: SpaceID
    ) {
        permissionController.setHostDecision(
            decision,
            for: hostPattern,
            extensionID: extensionID,
            in: spaceID,
            context: loadedContext(
                extensionID: extensionID,
                in: spaceID
            ),
            nativeMessagingCapability:
                runtimeContextController.nativeMessagingCapability
        )
    }

    func persistPermissionState(
        extensionID: String,
        in spaceID: SpaceID
    ) {
        runtimeContextController.persistPermissionState(
            extensionID: extensionID,
            in: spaceID
        )
    }
}
