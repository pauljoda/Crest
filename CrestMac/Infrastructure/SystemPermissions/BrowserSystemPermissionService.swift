import AVFoundation
import AppKit
import CoreLocation
import UserNotifications

@MainActor
final class BrowserSystemPermissionService: BrowserSystemPermissionServicing {
    private let location = BrowserGeolocationSystemService()
    private let folderAccess = BrowserSystemFolderAccess()

    func status(for permission: BrowserSystemPermission, spaceID: SpaceID?) async -> BrowserSystemPermissionStatus {
        switch permission {
        case .camera: return captureStatus(.video)
        case .microphone: return captureStatus(.audio)
        case .location:
            let enabled = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
            guard enabled else {
                return .init(
                    state: .blocked,
                    detail: String(localized: "Turn on Location Services for this Mac, then allow Crest."))
            }
            switch CLLocationManager().authorizationStatus {
            case .notDetermined: return .init(state: .notRequested)
            case .authorizedAlways, .authorizedWhenInUse: return .init(state: .allowed)
            case .denied: return .init(state: .blocked)
            case .restricted: return .init(state: .restricted)
            @unknown default: return .init(state: .unavailable)
            }
        case .notifications:
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined: return .init(state: .notRequested)
            case .denied: return .init(state: .blocked)
            case .authorized, .provisional, .ephemeral:
                return .init(
                    state: .allowed,
                    detail: settings.alertSetting == .disabled
                        ? String(localized: "Notifications are allowed, but banners are off in System Settings.") : nil)
            @unknown default: return .init(state: .unavailable)
            }
        case .passkeys:
            let access = BrowserPasskeyAccessController.shared
            access.refreshStatus()
            let state: BrowserSystemPermissionState
            switch access.status {
            case .checking: state = .checking
            case .notDetermined: state = .notRequested
            case .authorized: state = .allowed
            case .denied, .deviceNotConfigured: state = .blocked
            case .managedCapabilityRequired: state = .unavailable
            }
            let detail: String?
            switch access.status {
            case .authorized, .checking, .notDetermined: detail = nil
            case .denied: detail = access.status.detail
            case .deviceNotConfigured:
                detail = String(localized: "Finish setting up passkeys in System Settings, then check again.")
            case .managedCapabilityRequired:
                detail = String(
                    localized: "This build of Crest does not include permission to request browser passkey access.")
            }
            return .init(state: state, detail: detail)
        case .files: return folderAccess.status(spaceID: spaceID)
        }
    }

    func request(_ permission: BrowserSystemPermission, spaceID: SpaceID?) async throws {
        switch permission {
        case .camera: _ = await AVCaptureDevice.requestAccess(for: .video)
        case .microphone: _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .location:
            if await location.requestAuthorization() == .notDetermined {
                throw NSError(
                    domain: "BrowserSystemPermission", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(
                            localized:
                                "macOS has not returned a location decision. Respond to its prompt, or open System Settings > Privacy & Security > Location Services to allow Crest."
                        )
                    ])
            }
        case .notifications:
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        case .passkeys:
            BrowserPasskeyAccessController.shared.refreshStatus()
            await BrowserPasskeyAccessController.shared.requestAccess()
        case .files:
            guard let spaceID else { return }
            try await folderAccess.check(spaceID: spaceID)
        }
    }

    func chooseFolder(spaceID: SpaceID) async throws {
        try await folderAccess.chooseFolder(spaceID: spaceID)
    }

    func openSettings(for permission: BrowserSystemPermission) -> Bool {
        let destination: String
        switch permission {
        case .camera: destination = "com.apple.preference.security?Privacy_Camera"
        case .microphone: destination = "com.apple.preference.security?Privacy_Microphone"
        case .location: destination = "com.apple.preference.security?Privacy_LocationServices"
        case .notifications:
            destination =
                "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "com.pauldavis.crest")"
        case .passkeys: destination = "com.apple.preference.security"
        case .files: destination = "com.apple.preference.security?Privacy_FilesAndFolders"
        }
        guard let url = URL(string: "x-apple.systempreferences:\(destination)") else { return false }
        return NSWorkspace.shared.open(url)
    }

    private func captureStatus(_ type: AVMediaType) -> BrowserSystemPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: type) {
        case .authorized: .init(state: .allowed)
        case .notDetermined: .init(state: .notRequested)
        case .denied: .init(state: .blocked)
        case .restricted: .init(state: .restricted)
        @unknown default: .init(state: .unavailable)
        }
    }
}
