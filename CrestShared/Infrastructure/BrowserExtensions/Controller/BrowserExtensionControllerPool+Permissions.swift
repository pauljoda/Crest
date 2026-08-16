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

    func setPermissionDecision(
        _ decision: BrowserExtensionAccessDecision,
        for permission: String,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        let previous = permissionDecision(
            for: permission,
            extensionID: extensionID,
            in: space.id
        )
        guard previous != decision else { return }
        setPermissionDecision(
            decision,
            for: permission,
            extensionID: extensionID,
            in: space.id
        )
        try await restorationController.restartEnabledExtension(
            extensionID: extensionID,
            in: space
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

    func setHostDecision(
        _ decision: BrowserExtensionAccessDecision,
        for hostPattern: String,
        extensionID: String,
        in space: BrowserSpace
    ) async throws {
        let previous = hostDecision(
            for: hostPattern,
            extensionID: extensionID,
            in: space.id
        )
        guard previous != decision else { return }
        setHostDecision(
            decision,
            for: hostPattern,
            extensionID: extensionID,
            in: space.id
        )
        try await restorationController.restartEnabledExtension(
            extensionID: extensionID,
            in: space
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
