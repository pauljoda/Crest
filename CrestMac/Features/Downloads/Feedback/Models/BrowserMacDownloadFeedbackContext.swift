import Foundation

struct BrowserMacDownloadFeedbackContext: Equatable {
    var windowIdentifier: ObjectIdentifier?
    var profileID: UUID?
    var spaceID: SpaceID?
    var tabID: TabID?
    var bounds: CGRect
    var destination: CGRect?
    var isVisible: Bool
    var reduceMotion: Bool
}
