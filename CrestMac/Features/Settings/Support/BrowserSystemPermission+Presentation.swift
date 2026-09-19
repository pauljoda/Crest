import SwiftUI

extension BrowserSystemPermission {
    var title: LocalizedStringResource {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .location: "Location"
        case .notifications: "Notifications"
        case .passkeys: "Passkeys"
        case .files: "Files & Folders"
        }
    }

    var explanation: LocalizedStringResource {
        switch self {
        case .camera: "Use your camera on websites for video calls and other features."
        case .microphone: "Use your microphone on websites for calls and recording."
        case .location: "Share your location with websites you allow."
        case .notifications: "Show notifications from websites you allow."
        case .passkeys: "Sign in to websites using passkeys saved with your system providers."
        case .files: "Save downloads and open files you select."
        }
    }

    var symbol: String {
        switch self {
        case .camera: "camera.fill"
        case .microphone: "mic.fill"
        case .location: "location.fill"
        case .notifications: "bell.badge.fill"
        case .passkeys: "person.badge.key.fill"
        case .files: "folder.fill"
        }
    }

    var tint: Color {
        switch self {
        case .camera: .green
        case .microphone: .orange
        case .location: .blue
        case .notifications: .red
        case .passkeys: .purple
        case .files: .blue
        }
    }
}
