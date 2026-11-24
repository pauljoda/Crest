import AVFoundation
import SwiftUI
import UserNotifications

/// A macOS privacy permission the General pane checks and requests for Crest.
/// Each permission carries its row's title, where System Settings shows it,
/// and how the system API that owns it is read and asked.
struct BrowserSystemPermission: Hashable, Identifiable, Sendable {
    // MARK: - Types

    typealias StatusReader =
        @MainActor @Sendable (BrowserSystemPermissionService, UUID?) async -> BrowserSystemPermissionStatus
    typealias AccessRequest = @MainActor @Sendable (BrowserSystemPermissionService, UUID?) async throws -> Void

    // MARK: - Static Variables

    static let camera = BrowserSystemPermission(
        name: "camera", title: "Camera",
        settingsPane: "com.apple.preference.security?Privacy_Camera",
        status: { service, _ in await service.captureStatus(.video) },
        request: { _, _ in _ = await AVCaptureDevice.requestAccess(for: .video) })
    static let microphone = BrowserSystemPermission(
        name: "microphone", title: "Microphone",
        settingsPane: "com.apple.preference.security?Privacy_Microphone",
        status: { service, _ in await service.captureStatus(.audio) },
        request: { _, _ in _ = await AVCaptureDevice.requestAccess(for: .audio) })
    static let location = BrowserSystemPermission(
        name: "location", title: "Location",
        settingsPane: "com.apple.preference.security?Privacy_LocationServices",
        status: { service, _ in await service.locationStatus() },
        request: { service, _ in try await service.requestLocation() })
    static let notifications = BrowserSystemPermission(
        name: "notifications", title: "Notifications",
        settingsPane:
            "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? ProductIdentity.bundleIdentifier)",
        status: { service, _ in await service.notificationStatus() },
        request: { _, _ in
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        })
    static let passkeys = BrowserSystemPermission(
        name: "passkeys", title: "Passkeys",
        settingsPane: "com.apple.preference.security",
        status: { service, _ in await service.passkeyStatus() },
        request: { service, _ in
            service.passkeyAccess.refreshStatus()
            await service.passkeyAccess.requestAccess()
        })
    static let files = BrowserSystemPermission(
        name: "files", title: "Files & Folders",
        settingsPane: "com.apple.preference.security?Privacy_FilesAndFolders",
        checksSpaceFolder: true,
        status: { service, spaceID in service.folderAccess.status(spaceID: spaceID) },
        request: { service, spaceID in
            guard let spaceID else { return }
            try await service.folderAccess.check(spaceID: spaceID)
        })

    /// Every permission, in the order the pane lists them.
    static let all: [BrowserSystemPermission] = [camera, microphone, location, notifications, passkeys, files]

    // MARK: - Variables

    /// The spelling the row's accessibility identifier carries.
    let name: String

    let title: LocalizedStringResource

    /// Where System Settings shows the permission, after its URL scheme.
    let settingsPane: String

    /// The permission covers the selected Space's download folder rather than
    /// the app, so it is checked per Space and a folder can be chosen for it.
    let checksSpaceFolder: Bool

    /// Reads where the permission stands from its system API, for the selected
    /// Space where it covers one.
    let status: StatusReader

    /// Asks its system API for the permission.
    let request: AccessRequest

    var id: String { name }

    /// The System Settings page for the permission.
    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:\(settingsPane)")
    }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, settingsPane: String, checksSpaceFolder: Bool = false,
        status: @escaping StatusReader, request: @escaping AccessRequest
    ) {
        self.name = name
        self.title = title
        self.settingsPane = settingsPane
        self.checksSpaceFolder = checksSpaceFolder
        self.status = status
        self.request = request
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermission, rhs: BrowserSystemPermission) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// Where a permission stands, with the label, glyph and tone its row shows and
/// the button the row offers for it.
struct BrowserSystemPermissionState: Hashable, Sendable {
    // MARK: - Static Variables

    static let checking = BrowserSystemPermissionState(name: "checking", title: "Checking…")
    static let notRequested = BrowserSystemPermissionState(
        name: "notRequested", title: "Not requested",
        primaryAction: { row in
            if row.error != nil {
                Button("Open Settings", action: row.openSettings)
            } else {
                Button("Allow…", action: row.request)
            }
        })
    static let allowed = BrowserSystemPermissionState(
        name: "allowed", title: "Allowed", symbol: "checkmark.circle.fill", tone: .success,
        primaryAction: { row in
            Button(
                row.permission.checksSpaceFolder ? "Check Again" : "Settings…",
                action: row.permission.checksSpaceFolder ? row.request : row.openSettings)
        })
    static let blocked = BrowserSystemPermissionState(
        name: "blocked", title: "Needs attention", symbol: "exclamationmark.circle.fill", tone: .warning,
        primaryAction: { row in Button("Open Settings", action: row.openSettings) })
    static let restricted = BrowserSystemPermissionState(
        name: "restricted", title: "Restricted by macOS", symbol: "exclamationmark.circle.fill",
        tone: .warning,
        primaryAction: { row in Button("Open Settings", action: row.openSettings) })
    static let unavailable = BrowserSystemPermissionState(name: "unavailable", title: "Unavailable")
    static let notChecked = BrowserSystemPermissionState(
        name: "notChecked", title: "Not checked",
        primaryAction: { row in Button("Check Access", action: row.request) })
    static let chooseEachTime = BrowserSystemPermissionState(name: "chooseEachTime", title: "Ask where to save")

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String
    /// How the state reads; nil reads quietly.
    let tone: CrestStatusTone?

    /// The colour the row's label draws the state in.
    var tint: Color { tone?.color ?? .secondary }

    /// The button a row offers in this state, if any.
    let primaryAction: @MainActor @Sendable (BrowserSystemPermissionRow) -> Button<Text>?

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String = "circle.dashed", tone: CrestStatusTone? = nil,
        primaryAction: @escaping @MainActor @Sendable (BrowserSystemPermissionRow) -> Button<Text>? = { _ in nil }
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.tone = tone
        self.primaryAction = primaryAction
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermissionState, rhs: BrowserSystemPermissionState) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

struct BrowserSystemPermissionStatus: Equatable {
    var state: BrowserSystemPermissionState
    var detail: String? = nil
}
