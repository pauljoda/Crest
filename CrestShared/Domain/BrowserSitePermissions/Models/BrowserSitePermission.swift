import Foundation

enum BrowserSitePermission: String, Codable, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
    case location
    case notifications
    case popups
    case automaticDownloads
    case externalApplications
}
