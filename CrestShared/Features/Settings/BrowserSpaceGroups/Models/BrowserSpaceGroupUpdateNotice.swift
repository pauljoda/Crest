import Foundation

/// The one notice a device shows the first time a Space joins a group on it:
/// builds that predate Sub-Spaces show each Sub-Space on its own, signed out,
/// until they update.
@MainActor
enum BrowserSpaceGroupUpdateNotice {
    // MARK: - Static Variables

    static let message = String(localized: "Update Crest on your other devices to share sign-ins there.")

    private static let shownKey = "crest.subSpaces.updateNoticeShown"

    private static let defaults: UserDefaults = {
        let environment = BrowserLaunchEnvironment.current
        guard environment.requiresIsolation else { return .standard }
        let id = environment.persistentIsolationID ?? "ephemeral-\(UUID().uuidString)"
        return UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: id))!
    }()

    // MARK: - Actions - Showing

    /// A Space joined a group: the first group on this device shows the
    /// notice in the window the person looks at.
    static func showIfDue() {
        guard takeIfDue() else { return }
        BrowserNoticeCenter.shared.post(BrowserNotice(message: message, systemImage: "arrow.down.circle"))
    }

    /// Answers whether the notice is due, and marks it shown: true only the
    /// first time a group forms on this device.
    private static func takeIfDue() -> Bool {
        guard !defaults.bool(forKey: shownKey) else { return false }
        defaults.set(true, forKey: shownKey)
        return true
    }
}
