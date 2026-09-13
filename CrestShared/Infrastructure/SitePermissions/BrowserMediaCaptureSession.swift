import Observation
import WebKit

/// Stops active capture when a saved rule is revoked, including changes made
/// from Settings rather than the page's own controls.
@MainActor
final class BrowserMediaCaptureSession {
    private struct Grant: Hashable {
        let permission: BrowserMediaPermission
        let origin: BrowserSiteOrigin
    }

    private weak var webView: WKWebView?
    private let permissionCenter: BrowserSitePermissionCenter
    private let spaceID: SpaceID
    private var grants: [Grant: BrowserSitePermissionDecision] = [:]
    private var isObserving = false

    init(webView: WKWebView, permissionCenter: BrowserSitePermissionCenter, spaceID: SpaceID) {
        self.webView = webView
        self.permissionCenter = permissionCenter
        self.spaceID = spaceID
    }

    func recordGrant(_ permission: BrowserMediaPermission, origin: BrowserSiteOrigin) {
        grants[Grant(permission: permission, origin: origin)] = permissionCenter.mediaDecision(
            for: permission, origin: origin, in: spaceID
        )
        if !isObserving { observePermissionChanges() }
    }

    func reset() {
        grants.removeAll()
    }

    private func observePermissionChanges() {
        isObserving = true
        withObservationTracking {
            _ = permissionCenter.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                revokeChangedGrants()
                observePermissionChanges()
            }
        }
    }

    private func revokeChangedGrants() {
        for (grant, previous) in grants {
            let decision = permissionCenter.mediaDecision(
                for: grant.permission, origin: grant.origin, in: spaceID
            )
            guard decision != previous else { continue }
            if decision == .grantPersistently || decision == .grantForSession {
                grants[grant] = decision
                continue
            }
            grants.removeValue(forKey: grant)
            if grant.permission != .microphone {
                webView?.setCameraCaptureState(.none, completionHandler: nil)
            }
            if grant.permission != .camera {
                webView?.setMicrophoneCaptureState(.none, completionHandler: nil)
            }
        }
    }
}
