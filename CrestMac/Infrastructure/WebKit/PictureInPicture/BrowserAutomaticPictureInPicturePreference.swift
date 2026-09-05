import Foundation

enum BrowserAutomaticPictureInPicturePreference {
    static let key = "automaticallyEnterPictureInPicture"

    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: key) as? Bool ?? true
    }
}
