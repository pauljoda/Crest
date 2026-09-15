import Foundation

enum BrowserSystemPermission: String, CaseIterable, Identifiable {
    case camera, microphone, location, notifications, passkeys, files

    var id: String { rawValue }
}

enum BrowserSystemPermissionState: Equatable {
    case checking, notRequested, allowed, blocked, restricted, unavailable, notChecked, chooseEachTime
}

struct BrowserSystemPermissionStatus: Equatable {
    var state: BrowserSystemPermissionState
    var detail: String? = nil
}
