import Foundation
import Sparkle

@MainActor
protocol BrowserSoftwareUpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var sessionInProgress: Bool { get }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }

    func checkForUpdates()
    func checkForUpdatesInBackground()
    func resetUpdateCycleAfterShortDelay()
}

extension SPUUpdater: BrowserSoftwareUpdateChecking {}

/// Keeps Crest's refresh intent separate from Sparkle's download, validation,
/// and installation ownership. Sparkle remains the only component that selects,
/// verifies, downloads, resumes, skips, or installs an update.
@MainActor
final class BrowserSoftwareUpdateRefreshCoordinator {
    static let minimumAutomaticCheckInterval: TimeInterval = 60 * 60

    private enum PendingCheck {
        case userInitiated
        case background
    }

    private let updater: any BrowserSoftwareUpdateChecking
    private let model: BrowserSoftwareUpdateModel
    private var pendingCheck: PendingCheck?
    private var lastAutomaticRefreshRequestDate: Date?

    init(
        updater: any BrowserSoftwareUpdateChecking,
        model: BrowserSoftwareUpdateModel
    ) {
        self.updater = updater
        self.model = model
    }

    func updaterDidStart(at date: Date = Date()) {
        requestAutomaticRefreshIfDue(at: date)
    }

    func applicationDidBecomeActive(at date: Date = Date()) {
        requestAutomaticRefreshIfDue(at: date)
    }

    func checkForUpdates() {
        _ = request(.userInitiated)
    }

    func channelDidChange() {
        updater.resetUpdateCycleAfterShortDelay()

        guard updater.sessionInProgress else { return }
        pendingCheck = updater.automaticallyChecksForUpdates ? .background : nil
        guard
            model.beginRefreshingAvailableUpdate(
                suppressesWindowPresentation: true
            )
        else {
            pendingCheck = nil
            return
        }
    }

    func updateCycleDidFinish() {
        guard let pendingCheck else {
            model.finishRefreshIfNeeded()
            return
        }

        self.pendingCheck = nil
        guard start(pendingCheck) else {
            model.finishRefreshIfNeeded()
            return
        }
    }

    private func requestAutomaticRefreshIfDue(at date: Date) {
        guard updater.automaticallyChecksForUpdates else { return }
        let mostRecentCheck = [
            updater.lastUpdateCheckDate,
            lastAutomaticRefreshRequestDate,
        ].compactMap { $0 }.max()
        if let mostRecentCheck {
            guard
                date.timeIntervalSince(mostRecentCheck)
                    >= Self.minimumAutomaticCheckInterval
            else { return }
        }

        guard request(.background) else { return }
        lastAutomaticRefreshRequestDate = date
    }

    @discardableResult
    private func request(_ check: PendingCheck) -> Bool {
        if updater.sessionInProgress {
            let suppressesWindow = check == .background
            pendingCheck = check
            if model.beginRefreshingAvailableUpdate(
                suppressesWindowPresentation: suppressesWindow
            ) {
                return true
            }

            pendingCheck = nil
            if check == .userInitiated {
                if updater.canCheckForUpdates {
                    updater.checkForUpdates()
                } else {
                    model.focus()
                }
            }
            return false
        }

        return start(check)
    }

    private func start(_ check: PendingCheck) -> Bool {
        guard !updater.sessionInProgress, updater.canCheckForUpdates else {
            return false
        }
        switch check {
        case .userInitiated:
            updater.checkForUpdates()
        case .background:
            updater.checkForUpdatesInBackground()
        }
        return true
    }
}
