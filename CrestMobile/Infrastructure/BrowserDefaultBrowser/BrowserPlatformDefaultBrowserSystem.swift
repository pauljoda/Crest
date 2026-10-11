import Foundation
import UIKit

/// Whether Crest is the device's default browser. The system answers about
/// once a year, so Crest keeps the last answer it had and goes by it while the
/// system declines to answer again. A web link another app opens in Crest
/// answers too: only the default browser receives those.
@MainActor
enum BrowserPlatformDefaultBrowserSystem {
    // MARK: - Static Variables

    static let requestStyle = BrowserDefaultBrowserRequestStyle.systemSettings

    private static let lastAnswerKey = "crest.default-browser.last-answer"

    /// The last answer the system or an opened link gave, nil before either.
    private static var lastAnswer: Bool? {
        get { UserDefaults.standard.object(forKey: lastAnswerKey) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: lastAnswerKey) }
    }

    // MARK: - Actions - Status

    static func checkStatus() throws -> Bool {
        do {
            let isDefault = try UIApplication.shared.isDefault(.webBrowser)
            lastAnswer = isDefault
            return isDefault
        } catch {
            guard BrowserPlatformDefaultBrowserErrorPolicy.isRateLimited(error), let lastAnswer else { throw error }
            return lastAnswer
        }
    }

    /// Notes a link another app opened in Crest, which only the default
    /// browser receives when it is a web address.
    static func noteOpenedLink(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return }
        lastAnswer = true
    }

    // MARK: - Actions - Choosing

    static func requestDefault() async throws {
        openSettings()
    }

    static func openSettings() {
        guard
            let url = URL(
                string: UIApplication.openDefaultApplicationsSettingsURLString
            )
        else { return }
        UIApplication.shared.open(url)
    }
}
