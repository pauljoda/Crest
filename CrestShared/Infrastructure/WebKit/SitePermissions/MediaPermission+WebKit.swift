import WebKit

extension SitePermission {
    @MainActor
    func resolve(
        origin: SiteOrigin,
        topLevelOrigin: SiteOrigin,
        spaceID: SpaceID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter,
        requests: BrowserPagePermissionController,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        let decision = permissionCenter.mediaDecision(for: self, origin: origin, in: spaceID)
        guard decision.verdict == .ask else {
            decisionHandler(decision.grants ? .grant : .deny)
            return
        }
        requests.request(self, origin: origin, topLevelOrigin: topLevelOrigin, spaceName: spaceName) { response in
            guard let response, !permissionCenter.mediaDecision(for: self, origin: origin, in: spaceID).denies else {
                decisionHandler(.deny)
                return
            }
            if let savedDecision = response.savedDecision {
                permissionCenter.setDecision(savedDecision, for: self, origin: origin, in: spaceID)
            }
            decisionHandler(response.grants ? .grant : .deny)
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
