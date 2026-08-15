import Foundation
import Observation

/// Keeps Chrome Web Store installations current on a cadence.
///
/// One cancellable scheduled task is guarded by a generation counter, while a
/// forced pass coalesces rather than overlapping. Injectable clock and sleep
/// dependencies keep the schedule testable without waiting out a real week.
///
/// This model does **not** schedule from `init`. An update pass replaces live
/// extension packages, so it waits until launch
/// restoration has finished loading the installations it would be replacing.
@Observable
@MainActor
final class BrowserExtensionUpdateModel {
    private(set) var preferences: BrowserExtensionUpdatePreferences
    private(set) var isChecking = false
    private(set) var lastCheckedAt: Date?
    private(set) var lastErrorDescription: String?
    private(set) var lastUpdatedExtensionNames: [String] = []
    private(set) var updateRevision = 0

    @ObservationIgnored private let preferencesPersistence: any BrowserExtensionUpdatePreferencesPersisting
    @ObservationIgnored private let updateMetadataPersistence: any BrowserExtensionUpdateMetadataPersisting
    @ObservationIgnored private let checker: any BrowserExtensionUpdateChecking
    @ObservationIgnored private let applier: any BrowserExtensionUpdateApplying
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var scheduledCheckTask: Task<Void, Never>?
    @ObservationIgnored private var scheduledCheckGeneration = 0
    @ObservationIgnored private var pendingForcedCheck = false

    init(
        preferencesPersistence: any BrowserExtensionUpdatePreferencesPersisting,
        updateMetadataPersistence: any BrowserExtensionUpdateMetadataPersisting,
        checker: any BrowserExtensionUpdateChecking,
        applier: any BrowserExtensionUpdateApplying,
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.preferencesPersistence = preferencesPersistence
        self.updateMetadataPersistence = updateMetadataPersistence
        self.checker = checker
        self.applier = applier
        self.now = now
        self.sleep = sleep
        preferences = preferencesPersistence.load() ?? .default
        lastCheckedAt = updateMetadataPersistence.loadLastCheckedAt()
    }

    /// Whether a scheduled pass would find anything to do.
    var hasUpdatableExtensions: Bool {
        !updatableTargets().isEmpty
    }

    func setAutomaticUpdateEnabled(_ isEnabled: Bool) {
        guard isEnabled != preferences.isAutomaticUpdateEnabled else { return }
        var updated = preferences
        updated.isAutomaticUpdateEnabled = isEnabled
        replacePreferences(updated)
    }

    func setUpdateFrequency(_ frequency: BrowserExtensionUpdateFrequency) {
        guard frequency != preferences.updateFrequency else { return }
        var updated = preferences
        updated.updateFrequency = frequency
        replacePreferences(updated)
    }

    /// Arms the cadence. Called once launch restoration has settled, and again
    /// after every completed pass.
    func scheduleCheckIfNeeded() {
        guard preferences.isAutomaticUpdateEnabled,
            !isChecking,
            scheduledCheckTask == nil
        else {
            return
        }
        let delay = preferences.updateFrequency.timeUntilDue(
            lastCheckedAt: lastCheckedAt,
            now: now()
        )
        scheduleCheck(after: .seconds(delay), force: false)
    }

    /// **Check for Updates Now**: runs a pass regardless of the toggle or the
    /// cadence, because the person asking has just overridden both.
    func checkForUpdatesNow() async {
        cancelScheduledCheck()
        await check(force: true)
    }

    func cancelScheduledUpdates() {
        cancelScheduledCheck()
    }

    private func replacePreferences(
        _ updated: BrowserExtensionUpdatePreferences
    ) {
        preferences = updated
        preferencesPersistence.save(updated)
        cancelScheduledCheck()
        scheduleCheckIfNeeded()
    }

    /// Enabled Chrome Web Store rows only.
    ///
    /// A disabled installation is deliberately left alone. Applying an update
    /// means loading the replacement package into a live WebKit context, which
    /// would silently re-enable an extension somebody switched off; a package
    /// that is not running is also not exposed to anything. A disabled row
    /// rejoins the cadence on the first pass after it is switched back on.
    private func updatableTargets() -> [BrowserExtensionUpdateTarget] {
        applier.chromeWebStoreUpdateTargets().filter(\.isEnabled)
    }

    private func check(force: Bool) async {
        guard !isChecking else {
            if force { pendingForcedCheck = true }
            return
        }
        guard force || isDue else {
            scheduleCheckIfNeeded()
            return
        }
        let targets = updatableTargets()
        guard !targets.isEmpty else {
            recordPassCompletion(updatedNames: [], hadFailure: false)
            finishCheck(followUp: .scheduled)
            return
        }

        isChecking = true
        lastErrorDescription = nil
        var updatedNames: [String] = []
        var firstFailure: (any Error)?
        var successCount = 0

        for target in targets {
            if Task.isCancelled { break }
            do {
                guard
                    let published = try await checker.publishedVersion(
                        forExtension: target.extensionID
                    )
                else {
                    successCount += 1
                    continue
                }
                guard
                    BrowserExtensionVersionPolicy.isUpgrade(
                        from: target.installedVersion,
                        to: published
                    )
                else {
                    successCount += 1
                    continue
                }
                _ = try await applier.applyUpdate(to: target)
                successCount += 1
                updatedNames.append(target.displayName)
            } catch is CancellationError {
                finishCheck(followUp: .none)
                return
            } catch {
                firstFailure = firstFailure ?? error
            }
        }

        if Task.isCancelled {
            finishCheck(followUp: .none)
            return
        }

        recordPassCompletion(
            updatedNames: updatedNames,
            hadFailure: firstFailure != nil
        )
        lastErrorDescription = firstFailure?.localizedDescription
        // A pass where every single extension failed is the shape of being
        // offline, so it earns one short retry. A pass with any success is a
        // working network with one unhappy extension in it, and that retries
        // on the ordinary cadence rather than every hour forever.
        finishCheck(followUp: successCount == 0 ? .retry : .scheduled)
    }

    private var isDue: Bool {
        preferences.isAutomaticUpdateEnabled
            && preferences.updateFrequency.isDue(
                lastCheckedAt: lastCheckedAt,
                now: now()
            )
    }

    private func recordPassCompletion(
        updatedNames: [String],
        hadFailure: Bool
    ) {
        let checkedAt = now()
        lastCheckedAt = checkedAt
        updateMetadataPersistence.saveLastCheckedAt(checkedAt)
        lastUpdatedExtensionNames = updatedNames
        if !updatedNames.isEmpty {
            updateRevision &+= 1
        }
        if !hadFailure {
            lastErrorDescription = nil
        }
    }

    private func finishCheck(followUp: BrowserExtensionUpdateFollowUp) {
        isChecking = false
        if pendingForcedCheck {
            pendingForcedCheck = false
            scheduleCheck(after: .zero, force: true)
            return
        }
        switch followUp {
        case .none:
            break
        case .scheduled:
            scheduleCheckIfNeeded()
        case .retry:
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard preferences.isAutomaticUpdateEnabled else { return }
        scheduleCheck(after: Self.retryDelay, force: false)
    }

    private func scheduleCheck(after delay: Duration, force: Bool) {
        cancelScheduledCheck()
        let generation = scheduledCheckGeneration
        let sleep = sleep
        scheduledCheckTask = Task { [weak self] in
            do {
                if delay > .zero {
                    try await sleep(delay)
                } else {
                    try Task.checkCancellation()
                }
            } catch {
                return
            }
            await self?.runScheduledCheck(
                generation: generation,
                force: force
            )
        }
    }

    private func runScheduledCheck(generation: Int, force: Bool) async {
        guard generation == scheduledCheckGeneration,
            !Task.isCancelled
        else {
            return
        }
        scheduledCheckTask = nil
        await check(force: force)
    }

    private func cancelScheduledCheck() {
        scheduledCheckGeneration &+= 1
        scheduledCheckTask?.cancel()
        scheduledCheckTask = nil
    }

    private static let retryDelay = Duration.seconds(60 * 60)
}
