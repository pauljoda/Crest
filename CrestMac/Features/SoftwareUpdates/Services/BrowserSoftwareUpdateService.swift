import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class BrowserSoftwareUpdateService {
    static let channelPreferenceKey = "crest.software-update.channel"

    let model: BrowserSoftwareUpdateModel
    private(set) var isEnabled: Bool
    private(set) var startErrorDescription: String?
    var channel: BrowserSoftwareUpdateChannel {
        didSet {
            userDriver.channel = channel
            preferences?.set(channel.rawValue, forKey: Self.channelPreferenceKey)
            updater.resetUpdateCycleAfterShortDelay()
        }
    }

    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let userDriver: BrowserSoftwareUpdateUserDriver
    @ObservationIgnored private let updater: SPUUpdater

    init(
        isEnabled: Bool,
        preferences: UserDefaults? = .standard
    ) {
        let channel =
            BrowserSoftwareUpdateChannel(
                rawValue: preferences?.string(
                    forKey: Self.channelPreferenceKey
                ) ?? ""
            ) ?? .stable
        let model = BrowserSoftwareUpdateModel()
        let userDriver = BrowserSoftwareUpdateUserDriver(
            model: model,
            channel: channel
        )
        self.model = model
        self.isEnabled = isEnabled
        self.preferences = preferences
        self.channel = channel
        self.userDriver = userDriver
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: userDriver
        )

        guard isEnabled else { return }
        startUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        updater.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updater.automaticallyChecksForUpdates = isEnabled
    }

    func checkForUpdates() {
        guard isEnabled else {
            model.presentError(
                message: "Update checks are disabled in this isolated Crest session.",
                acknowledgement: {}
            )
            return
        }
        updater.checkForUpdates()
    }

    private func startUpdater() {
        do {
            try updater.start()
            startErrorDescription = nil
        } catch {
            isEnabled = false
            startErrorDescription = error.localizedDescription
            model.presentError(
                message: "Crest could not start software updates: \(error.localizedDescription)",
                acknowledgement: {}
            )
        }
    }
}
