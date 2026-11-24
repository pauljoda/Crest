import Foundation

/// The device-local records an older release kept in defaults before the
/// core's device store held them. The composition reads them at every launch
/// and the core adopts them once; the keys stay in place, so an older build
/// still finds them.
///
/// They are read from the defaults the launch's core store belongs to: the
/// installed app's own, a named isolated launch's suite, or none for a launch
/// that keeps everything in memory. A named isolated launch that syncs kept
/// its iCloud sync switch in a suite of its zone's own.
struct BrowserLegacyDeviceDefaults: Equatable, Sendable {
    // MARK: - Static Variables

    static let sitePermissionsKey = "crest.site-permissions.v1"
    static let shortcutsKey = "crest.keyboard-shortcuts.v1"
    static let linkPreferencesKey = "crest.link-preferences.v1"
    static let manualSetupDraftKey = "BrowserManualSetupDraft"
    static let setupCompletedKey = "crest.onboarding.completed"
    static let defaultPageZoomKey = "crest.page-zoom.default"
    static let backgroundPageActivityKey = "crest.webkit-inactive-scheduling-policy.v1"
    /// The WebKit flags the Mac kept, whose versioned slot held whether pages
    /// keep to 60 frames a second.
    static let webKitFlagsKey = "crest.webkit-feature-flag-overrides.v1"
    static let frameRateSlot = "PreferPageRenderingUpdatesNear60FPSEnabled.v2"
    static let cloudSyncEnabledKey = "crest.cloud-sync.enabled"
    /// The prefix of each Space's download choices, which the Mac kept as
    /// `browser.download.space.<id>.asksWhere`, `.directoryName` and
    /// `.directoryBookmark`.
    static let spaceDownloadsPrefix = "browser.download.space."

    // MARK: - Variables

    /// The saved site permission document, or nil when none was saved.
    var sitePermissions: Data?
    /// The saved shortcut choices, or nil when none were saved.
    var shortcuts: Data?
    /// The saved link preferences, or nil when none were saved.
    var linkPreferences: Data?
    /// The unfinished manual setup, or nil when none was saved.
    var manualSetupDraft: Data?
    /// Whether setup was completed on this device. A launch that keeps
    /// everything in memory, and so reads no defaults, counts as having
    /// completed it.
    var setupCompleted = true
    /// The page, download and iCloud sync choices the release kept, which the
    /// core carries each once.
    var preferences = AdoptDevicePreferences(
        defaultPageZoom: nil, backgroundPageActivity: nil, allowsHighFrameRate: nil, syncsWithICloud: nil, downloads: []
    )

    // MARK: - Actions - Reading

    static func read(
        for environment: BrowserLaunchEnvironment,
        standard: UserDefaults = .standard,
        cloudConfiguration: BrowserCloudSyncConfiguration? = .configured()
    ) -> BrowserLegacyDeviceDefaults {
        let defaults: UserDefaults? =
            environment.requiresIsolation
            ? environment.persistentIsolationID.flatMap {
                UserDefaults(suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: $0))
            }
            : standard
        let cloudDefaults: UserDefaults? =
            environment.requiresIsolation
            ? environment.persistentIsolationID.flatMap { isolationID in
                cloudConfiguration?.isolated(for: environment).flatMap {
                    UserDefaults(
                        suiteName: BrowserLaunchEnvironment.isolatedDefaultsSuiteName(isolationID: isolationID)
                            + ".cloud." + $0.zoneName)
                }
            }
            : standard
        return BrowserLegacyDeviceDefaults(
            sitePermissions: defaults?.data(forKey: sitePermissionsKey),
            shortcuts: defaults?.data(forKey: shortcutsKey),
            linkPreferences: defaults?.data(forKey: linkPreferencesKey),
            manualSetupDraft: defaults?.data(forKey: manualSetupDraftKey),
            setupCompleted: defaults?.bool(forKey: setupCompletedKey) ?? true,
            preferences: defaults.map { preferences(in: $0, cloud: cloudDefaults) }
                ?? BrowserLegacyDeviceDefaults().preferences)
    }

    /// The page and download choices `defaults` holds, and the iCloud sync
    /// switch `cloud` holds.
    private static func preferences(in defaults: UserDefaults, cloud: UserDefaults?) -> AdoptDevicePreferences {
        let frameRate = (defaults.dictionary(forKey: webKitFlagsKey)?[frameRateSlot] as? String)
            .flatMap(BrowserWebKitFrameRateSlot.init(rawValue:))
        return AdoptDevicePreferences(
            defaultPageZoom: defaults.object(forKey: defaultPageZoomKey) == nil
                ? nil : defaults.double(forKey: defaultPageZoomKey),
            backgroundPageActivity: defaults.string(forKey: backgroundPageActivityKey),
            allowsHighFrameRate: frameRate.map { $0 == .disabled },
            syncsWithICloud: cloud?.object(forKey: cloudSyncEnabledKey) == nil
                ? nil : cloud?.bool(forKey: cloudSyncEnabledKey),
            downloads: spaceDownloads(in: defaults))
    }

    /// Each Space's download choices `defaults` holds, by the Space its keys
    /// name. A folder kept without its name or its token is left out.
    private static func spaceDownloads(in defaults: UserDefaults) -> [SpaceDownloadPreferences] {
        let spaceIDs = Set(
            defaults.dictionaryRepresentation().keys.compactMap { key -> UUID? in
                guard key.hasPrefix(spaceDownloadsPrefix) else { return nil }
                return UUID(uuidString: String(key.dropFirst(spaceDownloadsPrefix.count).prefix(36)))
            })
        return spaceIDs.sorted { $0.uuidString < $1.uuidString }.map { spaceID in
            let prefix = spaceDownloadsPrefix + spaceID.uuidString.lowercased() + "."
            let folder = defaults.string(forKey: prefix + "directoryName").flatMap { name in
                defaults.data(forKey: prefix + "directoryBookmark").map { DownloadFolder(name: name, token: $0) }
            }
            return SpaceDownloadPreferences(
                spaceID: spaceID, asksWhereToSave: defaults.bool(forKey: prefix + "asksWhere"), folder: folder)
        }
    }
}

/// What the Mac's versioned frame-rate slot held: whether pages keep to 60
/// frames a second.
private enum BrowserWebKitFrameRateSlot: String {
    case enabled
    case disabled
}
