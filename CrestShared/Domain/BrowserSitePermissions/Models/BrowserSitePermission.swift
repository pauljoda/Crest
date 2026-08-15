import Foundation

enum BrowserSitePermission: String, Codable, CaseIterable, Hashable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
    case popups
    case automaticDownloads
    case externalApplications

}
