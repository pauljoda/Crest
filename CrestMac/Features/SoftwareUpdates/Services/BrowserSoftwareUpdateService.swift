import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class BrowserSoftwareUpdateService {
    static let channelPreferenceKey = "crest.software-update.channel"
    static let bundledChannelPreferenceKey =
        "crest.software-update.bundled-channel"
    static let defaultChannelInfoKey = "CrestDefaultUpdateChannel"

    let model: BrowserSoftwareUpdateModel
    let widgetSource: BrowserSoftwareUpdateWidgetSource
    private(set) var isEnabled: Bool
    private(set) var startErrorDescription: String?
    var channel: BrowserSoftwareUpdateChannel {
        didSet {
            userDriver.channel = channel
            preferences?.set(channel.rawValue, forKey: Self.channelPreferenceKey)
            guard isEnabled else { return }
            refreshCoordinator.channelDidChange()
        }
    }

    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let userDriver: BrowserSoftwareUpdateUserDriver
    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private let refreshCoordinator: BrowserSoftwareUpdateRefreshCoordinator

    init(
        isEnabled: Bool,
        preferences: UserDefaults? = .standard,
        defaultChannel: BrowserSoftwareUpdateChannel? = nil,
        feedURLOverride: URL? = nil
    ) {
        let bundledDefaultChannel =
            defaultChannel
            ?? BrowserSoftwareUpdateChannel(
                rawValue: Bundle.main.object(
                    forInfoDictionaryKey: Self.defaultChannelInfoKey
                ) as? String ?? ""
            )
            ?? .stable
        let channel = Self.launchChannel(
            bundledDefault: bundledDefaultChannel,
            preferences: preferences
        )
        let widgetSource = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: widgetSource)
        let userDriver = BrowserSoftwareUpdateUserDriver(
            model: model,
            channel: channel,
            feedURLOverride: feedURLOverride
        )
        self.model = model
        self.widgetSource = widgetSource
        self.isEnabled = isEnabled
        self.preferences = preferences
        self.channel = channel
        self.userDriver = userDriver
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: userDriver
        )
        let refreshCoordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        self.updater = updater
        self.refreshCoordinator = refreshCoordinator
        userDriver.updateCycleDidFinish = { [weak refreshCoordinator] in
            refreshCoordinator?.updateCycleDidFinish()
        }

        guard isEnabled else { return }
        startUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        updater.automaticallyChecksForUpdates
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updater.automaticallyChecksForUpdates = isEnabled
    }

    var automaticallyDownloadsUpdates: Bool {
        updater.automaticallyDownloadsUpdates
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        updater.automaticallyDownloadsUpdates = isEnabled
    }

    func checkForUpdates() {
        guard isEnabled else {
            model.presentError(
                message: "Update checks are disabled in this isolated Crest session.",
                acknowledgement: {}
            )
            return
        }
        refreshCoordinator.checkForUpdates()
    }

    func applicationDidBecomeActive() {
        guard isEnabled else { return }
        refreshCoordinator.applicationDidBecomeActive()
    }

    /// Presents updater states for an explicitly isolated verification launch.
    /// It never starts Sparkle or reads an appcast, and is deliberately absent
    /// from the production launch path.
    func presentIsolatedSidebarWidgetFixture(_ description: String) {
        guard !isEnabled else { return }
        let components = description.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: true
        ).map(String.init)
        let state = components.first ?? "available"
        let version = components.count > 1 ? components[1] : "0.5.99"
        let build = components.count > 2 ? components[2] : "599"
        model.presentUpdate(
            title: "Crest \(version)",
            version: version,
            build: build,
            isInformationOnly: false,
            isFixture: true,
            suppressesWindowPresentation: true,
            install: {},
            skip: {}
        )
        switch state {
        case "checking":
            model.presentChecking(cancellation: {})
        case "automatic-downloading":
            model.presentAutomaticDownload(
                title: "Crest \(version)",
                version: version,
                build: build,
                releaseNotes: nil,
                informationURL: nil,
                isFixture: true
            )
        case "downloading":
            model.presentDownload(cancellation: {})
            model.setExpectedDownloadLength(100)
            model.receiveDownloadedBytes(42)
        case "automatic-ready":
            model.presentAutomaticUpdateReady(
                title: "Crest \(version)",
                version: version,
                build: build,
                releaseNotes: nil,
                informationURL: nil,
                isFixture: true,
                installAndRelaunch: { [weak model] in
                    model?.presentInstalling(
                        applicationTerminated: true,
                        retryTermination: {}
                    )
                }
            )
        case "ready":
            model.presentReadyToInstall(
                install: { [weak model] in
                    model?.presentInstalling(
                        applicationTerminated: true,
                        retryTermination: {}
                    )
                },
                cancel: {}
            )
        case "failed":
            model.presentError(
                message: "This isolated fixture simulates an update error.",
                acknowledgement: {}
            )
        default:
            break
        }
    }

    private func startUpdater() {
        do {
            try updater.start()
            startErrorDescription = nil
            refreshCoordinator.updaterDidStart()
        } catch {
            isEnabled = false
            startErrorDescription = error.localizedDescription
            model.presentError(
                message: "Crest could not start software updates: \(error.localizedDescription)",
                acknowledgement: {}
            )
        }
    }

    private static func launchChannel(
        bundledDefault: BrowserSoftwareUpdateChannel,
        preferences: UserDefaults?
    ) -> BrowserSoftwareUpdateChannel {
        let previousBundledChannel = preferences?.string(
            forKey: bundledChannelPreferenceKey
        )
        guard previousBundledChannel == bundledDefault.rawValue else {
            preferences?.set(
                bundledDefault.rawValue,
                forKey: bundledChannelPreferenceKey
            )
            preferences?.set(
                bundledDefault.rawValue,
                forKey: channelPreferenceKey
            )
            return bundledDefault
        }
        return BrowserSoftwareUpdateChannel(
            rawValue: preferences?.string(
                forKey: channelPreferenceKey
            ) ?? ""
        ) ?? bundledDefault
    }
}
