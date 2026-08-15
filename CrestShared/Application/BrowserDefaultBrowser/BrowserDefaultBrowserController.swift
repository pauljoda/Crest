import Foundation
import Observation

@Observable
@MainActor
final class BrowserDefaultBrowserController {
    typealias StatusCheck = @MainActor () throws -> Bool
    typealias DefaultRequest = @MainActor () async throws -> Void
    typealias SettingsOpener = @MainActor () -> Void

    private(set) var status = BrowserDefaultBrowserStatus.unknown
    private(set) var isWorking = false
    let requestStyle: BrowserDefaultBrowserRequestStyle

    @ObservationIgnored private let statusCheck: StatusCheck
    @ObservationIgnored private let defaultRequest: DefaultRequest
    @ObservationIgnored private let settingsOpener: SettingsOpener

    init(
        requestStyle: BrowserDefaultBrowserRequestStyle =
            BrowserPlatformDefaultBrowserSystem.requestStyle,
        statusCheck: @escaping StatusCheck =
            BrowserPlatformDefaultBrowserSystem.checkStatus,
        defaultRequest: @escaping DefaultRequest =
            BrowserPlatformDefaultBrowserSystem.requestDefault,
        settingsOpener: @escaping SettingsOpener =
            BrowserPlatformDefaultBrowserSystem.openSettings
    ) {
        self.requestStyle = requestStyle
        self.statusCheck = statusCheck
        self.defaultRequest = defaultRequest
        self.settingsOpener = settingsOpener
    }

    func refreshStatus() {
        do {
            status = try statusCheck() ? .isDefault : .notDefault
        } catch {
            status = .unavailable(Self.userFacingDescription(for: error))
        }
    }

    func requestDefault() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await defaultRequest()
            refreshStatus()
        } catch {
            status = .unavailable(Self.userFacingDescription(for: error))
        }
    }

    func openSystemSettings() {
        settingsOpener()
    }

    private static func userFacingDescription(for error: any Error) -> String {
        if let platformDescription =
            BrowserPlatformDefaultBrowserErrorPolicy.userFacingDescription(
                for: error
            ) {
            return platformDescription
        }

        let message = error.localizedDescription.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return message.isEmpty
            ? "The system could not determine the default browser."
            : message
    }
}
