import Foundation

enum BrowserMediaPermission: String, Codable, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone

    var sitePermission: BrowserSitePermission {
        switch self {
        case .camera:
            .camera
        case .microphone:
            .microphone
        case .cameraAndMicrophone:
            .cameraAndMicrophone
        }
    }
}
