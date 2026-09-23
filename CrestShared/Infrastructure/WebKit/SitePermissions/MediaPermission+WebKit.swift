import WebKit

extension BrowserMediaPermission {
    @MainActor
    func resolve(
        origin: BrowserSiteOrigin,
        topLevelOrigin: BrowserSiteOrigin,
        spaceID: SpaceID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter,
        requests: BrowserPagePermissionController,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        switch permissionCenter.mediaDecision(for: self, origin: origin, in: spaceID) {
        case .grantForSession, .grantPersistently:
            decisionHandler(.grant)
        case .denyForSession, .denyPersistently:
            decisionHandler(.deny)
        case .ask:
            requests.request(
                sitePermission, origin: origin, topLevelOrigin: topLevelOrigin,
                spaceName: spaceName
            ) { response in
                guard let response else {
                    decisionHandler(.deny)
                    return
                }
                let latest = permissionCenter.mediaDecision(for: self, origin: origin, in: spaceID)
                if latest == .denyPersistently || latest == .denyForSession {
                    decisionHandler(.deny)
                    return
                }
                switch response {
                case .allowOnce:
                    decisionHandler(.grant)
                case .denyOnce:
                    decisionHandler(.deny)
                case .grantPersistently, .denyPersistently:
                    permissionCenter.setDecision(
                        response == .grantPersistently ? .grantPersistently : .denyPersistently,
                        for: sitePermission, origin: origin, in: spaceID
                    )
                    decisionHandler(response == .grantPersistently ? .grant : .deny)
                }
            }
        }
    }

    init(_ captureType: WKMediaCaptureType) {
        switch captureType {
        case .camera:
            self = .camera
        case .microphone:
            self = .microphone
        case .cameraAndMicrophone:
            self = .cameraAndMicrophone
        @unknown default:
            self = .cameraAndMicrophone
        }
    }
}
