import SwiftUI

/// A macOS privacy permission the General pane checks and requests for Crest.
/// Each permission carries its row's text, glyph and tint, and where System
/// Settings shows it.
struct BrowserSystemPermission: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each permission is read and requested through its own system API, so
    /// the one place that calls those APIs switches over the kind.
    enum Kinds: Sendable {
        case camera
        case microphone
        case location
        case notifications
        case passkeys
        case files
    }

    // MARK: - Variables

    static let camera = BrowserSystemPermission(
        kind: .camera, name: "camera", title: "Camera",
        explanation: "Use your camera on websites for video calls and other features.", symbol: "camera.fill",
        tint: .green, settingsPane: "com.apple.preference.security?Privacy_Camera")
    static let microphone = BrowserSystemPermission(
        kind: .microphone, name: "microphone", title: "Microphone",
        explanation: "Use your microphone on websites for calls and recording.", symbol: "mic.fill", tint: .orange,
        settingsPane: "com.apple.preference.security?Privacy_Microphone")
    static let location = BrowserSystemPermission(
        kind: .location, name: "location", title: "Location",
        explanation: "Share your location with websites you allow.", symbol: "location.fill", tint: .blue,
        settingsPane: "com.apple.preference.security?Privacy_LocationServices")
    static let notifications = BrowserSystemPermission(
        kind: .notifications, name: "notifications", title: "Notifications",
        explanation: "Show notifications from websites you allow.", symbol: "bell.badge.fill", tint: .red,
        settingsPane:
            "com.apple.Notifications-Settings.extension?id=\(Bundle.main.bundleIdentifier ?? "com.pauldavis.crest")")
    static let passkeys = BrowserSystemPermission(
        kind: .passkeys, name: "passkeys", title: "Passkeys",
        explanation: "Sign in to websites using passkeys saved with your system providers.",
        symbol: "person.badge.key.fill", tint: .purple, settingsPane: "com.apple.preference.security")
    static let files = BrowserSystemPermission(
        kind: .files, name: "files", title: "Files & Folders", explanation: "Save downloads and open files you select.",
        symbol: "folder.fill", tint: .blue, settingsPane: "com.apple.preference.security?Privacy_FilesAndFolders",
        checksSpaceFolder: true)

    /// Every permission, in the order the pane lists them.
    static let all: [BrowserSystemPermission] = [camera, microphone, location, notifications, passkeys, files]

    let kind: Kinds

    /// The spelling the row's accessibility identifier carries.
    let name: String

    let title: LocalizedStringResource
    let explanation: LocalizedStringResource
    let symbol: String
    let tint: Color

    /// Where System Settings shows the permission, after its URL scheme.
    let settingsPane: String

    /// The permission covers the selected Space's download folder rather than
    /// the app, so it is checked per Space and a folder can be chosen for it.
    let checksSpaceFolder: Bool

    var id: String { name }

    /// The System Settings page for the permission.
    var settingsURL: URL? {
        URL(string: "x-apple.systempreferences:\(settingsPane)")
    }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, explanation: LocalizedStringResource,
        symbol: String, tint: Color, settingsPane: String, checksSpaceFolder: Bool = false
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.explanation = explanation
        self.symbol = symbol
        self.tint = tint
        self.settingsPane = settingsPane
        self.checksSpaceFolder = checksSpaceFolder
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermission, rhs: BrowserSystemPermission) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// Where a permission stands, with the label, glyph and tint its row shows.
struct BrowserSystemPermissionState: Hashable, Sendable {
    // MARK: - Types

    /// The row offers a different control in each state, so the row's one
    /// control switch reads the kind.
    enum Kinds: Sendable {
        case checking
        case notRequested
        case allowed
        case blocked
        case restricted
        case unavailable
        case notChecked
        case chooseEachTime
    }

    // MARK: - Variables

    static let checking = BrowserSystemPermissionState(kind: .checking, title: "Checking…")
    static let notRequested = BrowserSystemPermissionState(kind: .notRequested, title: "Not requested")
    static let allowed = BrowserSystemPermissionState(
        kind: .allowed, title: "Allowed", symbol: "checkmark.circle.fill", tint: .green)
    static let blocked = BrowserSystemPermissionState(
        kind: .blocked, title: "Needs attention", symbol: "exclamationmark.circle.fill", tint: .orange)
    static let restricted = BrowserSystemPermissionState(
        kind: .restricted, title: "Restricted by macOS", symbol: "exclamationmark.circle.fill", tint: .orange)
    static let unavailable = BrowserSystemPermissionState(kind: .unavailable, title: "Unavailable")
    static let notChecked = BrowserSystemPermissionState(kind: .notChecked, title: "Not checked")
    static let chooseEachTime = BrowserSystemPermissionState(kind: .chooseEachTime, title: "Ask where to save")

    let kind: Kinds
    let title: LocalizedStringResource
    let symbol: String
    let tint: Color

    // MARK: - Initializers

    private init(
        kind: Kinds, title: LocalizedStringResource, symbol: String = "circle.dashed", tint: Color = .secondary
    ) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSystemPermissionState, rhs: BrowserSystemPermissionState) -> Bool {
        lhs.kind == rhs.kind
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
    }
}

struct BrowserSystemPermissionStatus: Equatable {
    var state: BrowserSystemPermissionState
    var detail: String? = nil
}
