import Foundation

/// The App Group Crest and its share extension both open: the preference,
/// saved links and Space list the extension reads without loading the core.
struct BrowserLinkSharingContainer: @unchecked Sendable {
    // MARK: - Static Variables

    /// The Info.plist key both bundles carry with the group's identifier.
    private static let groupIdentifierKey = "CrestAppGroupIdentifier"

    /// The group this bundle names, or nil when the build carries none or is
    /// not entitled to it, such as an unsigned review build.
    static var bundled: BrowserLinkSharingContainer? {
        guard
            let identifier = Bundle.main.object(forInfoDictionaryKey: groupIdentifierKey) as? String,
            !identifier.isEmpty,
            let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier),
            let defaults = UserDefaults(suiteName: identifier)
        else { return nil }
        return BrowserLinkSharingContainer(defaults: defaults, directory: directory)
    }

    // MARK: - Variables

    let defaults: UserDefaults
    let directory: URL

    // MARK: - Initializers

    init(defaults: UserDefaults, directory: URL) {
        self.defaults = defaults
        self.directory = directory
    }

    // MARK: - Actions - Preferences

    /// What a link shared to Crest does, as the person last chose it.
    var linkOpening: BrowserSharedLinkOpening {
        BrowserSharedLinkOpening.stored(in: defaults)
    }

    /// The links the extension saved for Crest to open.
    var inbox: BrowserSharedLinkInbox {
        BrowserSharedLinkInbox(defaults: defaults)
    }
}
