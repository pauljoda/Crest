import Foundation

extension BrowserSettingsDestination {
    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .links: "Links"
        case .shortcuts: "Shortcuts"
        case .spaces: "Spaces"
        case .sync: "Sync"
        case .privacy: "Privacy & Permissions"
        case .passwords: "Passwords"
        case .extensions: "Extensions"
        case .featureFlags: "Feature Flags"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    /// The title where space is tight enough that the full name wraps.
    ///
    /// Only privacy differs: the macOS sidebar row cannot fit
    /// "Privacy & Permissions" on one line at its compact row height.
    var navigationTitle: LocalizedStringResource {
        switch self {
        case .privacy: "Privacy"
        default: title
        }
    }

    var subtitle: LocalizedStringResource {
        switch self {
        case .general: "Browsing and interface"
        case .links: "Quick Window and Peek"
        case .shortcuts: "Keyboard commands"
        case .spaces: "Profiles and appearance"
        case .sync: "iCloud setup and status"
        case .privacy: "Site access and data"
        case .passwords: "Credentials and autofill"
        case .extensions: "Space-specific add-ons"
        case .featureFlags: "WebKit experiments"
        case .advanced: "Import, export, and runtime"
        case .about: "Version, updates, and support"
        }
    }

    /// Localized vocabulary that supplements the visible destination metadata.
    ///
    /// The terms are the union of the vocabulary each platform used before this
    /// catalog was shared, so neither shell loses a search route.
    var searchTerms: LocalizedStringResource {
        switch self {
        case .general:
            "browser startup default Space transparency sidebar interface page zoom percentage typing spelling spell check text editing focus new tabs Command-click middle-click"
        case .links:
            "external apps Quick Window Peek pinned saved routing open"
        case .shortcuts:
            "keyboard keys commands rebind remap Arc hotkeys navigation tabs Spaces page"
        case .spaces:
            "profile name identity icon color appearance theme search cleanup isolation reorder browsing archive independence"
        case .sync:
            "iCloud CloudKit account upload download conflict status monitor diagnostics pending records"
        case .privacy:
            "content blocking ads trackers camera microphone site access history cookies data"
        case .passwords:
            "credentials autofill iCloud Keychain passkeys synchronization"
        case .extensions:
            "WebExtension add-ons permissions storage"
        case .featureFlags:
            "WebKit experimental preview testable developer stable runtime flags features"
        case .advanced:
            "import export backup portability data records"
        case .about:
            "version build updates changelog what's new feedback Reddit GitHub issues roadmap support community"
        }
    }

    /// The concrete localized haystack used only while filtering Settings.
    /// Presentation remains deferred through ``LocalizedStringResource``.
    private func searchIndex(locale: Locale) -> String {
        [title, navigationTitle, subtitle, searchTerms]
            .map { resource in
                var localizedResource = resource
                localizedResource.locale = locale
                return String(localized: localizedResource)
            }
            .joined(separator: " ")
    }

    func matchesSearchQuery(_ query: String, locale: Locale) -> Bool {
        searchIndex(locale: locale).range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: locale
        ) != nil
    }
}
