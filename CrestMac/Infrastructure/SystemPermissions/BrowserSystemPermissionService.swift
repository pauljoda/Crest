import AVFoundation
import AppKit
import CoreLocation
import UserNotifications

@MainActor
final class BrowserSystemPermissionService: BrowserSystemPermissionServicing {
    private let location = BrowserGeolocationSystemService()
    private let folderAccess = BrowserSystemFolderAccess()
    private let readPasskeyStatus: @Sendable () -> BrowserPasskeyAccessStatus

    init(
        readPasskeyStatus: @escaping @Sendable () -> BrowserPasskeyAccessStatus = BrowserSystemPermissionService
            .passkeyStatus
    ) {
        self.readPasskeyStatus = readPasskeyStatus
    }

    func status(for permission: BrowserSystemPermission, spaceID: SpaceID?) async -> BrowserSystemPermissionStatus {
        switch permission {
        case .camera: return await captureStatus(.video)
        case .microphone: return await captureStatus(.audio)
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
            let readPasskeyStatus = readPasskeyStatus
            // These read-only APIs can wait for synchronous system IPC.
            // Keep that wait away from the UI while General settings opens.
            let status = await Task.detached(priority: .userInitiated) { readPasskeyStatus() }.value
            let state: BrowserSystemPermissionState
            switch status {
            case .checking: state = .checking
            case .notDetermined: state = .notRequested
            case .authorized: state = .allowed
            case .denied, .deviceNotConfigured: state = .blocked
            case .managedCapabilityRequired: state = .unavailable
            }
            let detail: String?
            switch status {
            case .authorized, .checking, .notDetermined: detail = nil
            case .denied: detail = status.detail
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

    nonisolated private static func passkeyStatus() -> BrowserPasskeyAccessStatus {
        guard BrowserPasskeyAccessSystem.hasManagedCapability() else { return .managedCapabilityRequired }
        return BrowserPasskeyAccessPolicy.status(
            hasManagedCapability: true,
            deviceConfiguration: BrowserPasskeyAccessSystem.deviceConfiguration(),
            authorizationState: BrowserPasskeyAccessSystem.authorizationState()
        )
    }

    private func captureStatus(_ type: AVMediaType) async -> BrowserSystemPermissionStatus {
        let status = await Task.detached(priority: .userInitiated) {
            AVCaptureDevice.authorizationStatus(for: type)
        }.value
        return switch status {
        case .authorized: .init(state: .allowed)
        case .notDetermined: .init(state: .notRequested)
        case .denied: .init(state: .blocked)
        case .restricted: .init(state: .restricted)
        @unknown default: .init(state: .unavailable)
        }
    }
}
