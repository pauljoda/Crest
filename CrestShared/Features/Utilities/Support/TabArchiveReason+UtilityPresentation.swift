import SwiftUI

extension TabArchiveReason {
    var utilityTitle: LocalizedStringResource {
        switch self {
        case .autoCleanup: "Automatically cleaned"
        case .closed: "Closed"
        case .deleted: "Deleted"
        case .deletedOnAnotherDevice: "Deleted on another device"
        case .quickWindow: "Quick Window"
        case .synced: "Synced from another device"
        }
    }

    var utilitySystemImage: String {
        switch self {
        case .autoCleanup: "archivebox.fill"
        case .closed: "xmark.circle.fill"
        case .deleted, .deletedOnAnotherDevice: "trash.fill"
        case .quickWindow: "timer"
        case .synced: "icloud.and.arrow.down.fill"
        }
    }

    var utilityTint: Color {
        switch self {
        case .autoCleanup: .orange
        case .closed: .red
        case .deleted, .deletedOnAnotherDevice: .red
        case .quickWindow: .purple
        case .synced: .blue
        }
    }
}
