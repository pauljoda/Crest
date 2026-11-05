import Foundation

/// A transient message at the top of a browser window. It asks nothing of the
/// person: anything that needs a decision is a dialog, and everything else
/// that Crest reports — a copy, a zoom change, an action that could not run —
/// is one of these. It may offer one action that undoes what it reports, such
/// as moving a page back to the engine it left.
struct BrowserNotice: Equatable, Hashable {
    // MARK: - Static Variables

    static let urlCopied = BrowserNotice(
        message: String(localized: "URL Copied"),
        systemImage: "checkmark.circle.fill"
    )

    static let copied = BrowserNotice(
        message: String(localized: "Copied"),
        systemImage: "checkmark.circle.fill"
    )

    static let openedInBackgroundTab = BrowserNotice(
        message: String(localized: "Opened in Background Tab"),
        systemImage: "plus.square.on.square"
    )

    // MARK: - Variables

    let message: String
    let systemImage: String
    var action: BrowserNoticeAction?
    /// What VoiceOver reads when the words alone would leave out what they
    /// report, as a bare zoom percentage does; nil reads the message.
    var accessibilityLabel: String?

    /// Long enough to read: short confirmations leave quickly, sentences stay,
    /// and one that offers an action stays longest, so the person can take it.
    var duration: Duration {
        guard action == nil else { return BrowserRootMetrics.noticeLongestDuration }
        let reading = Duration.milliseconds(message.count * 60)
        return min(max(BrowserRootMetrics.noticeDuration, reading), BrowserRootMetrics.noticeLongestDuration)
    }

    // MARK: - Actions - Notices

    /// The page's zoom, as `label` names it.
    static func pageZoom(_ label: String) -> BrowserNotice {
        BrowserNotice(
            message: label, systemImage: "textformat.size",
            accessibilityLabel: String(localized: "Page zoom \(label)"))
    }

    /// What the window says once clearing one site's `category` ended:
    /// cleared by every engine, or not.
    static func siteData(_ category: BrowsingDataCategory, cleared: Bool) -> BrowserNotice {
        let title = (cleared ? category.clearedTitle : category.failedTitle) ?? category.title
        return BrowserNotice(
            message: String(localized: title),
            systemImage: cleared ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
    }

    /// A page kept `shortcut`, and pressing it again runs `command`.
    static func pressAgain(_ shortcut: BrowserShortcut, for command: ShortcutCommand) -> BrowserNotice {
        BrowserNotice(
            message: String(localized: "Press \(shortcut.displayString) Again to \(command.title())"),
            systemImage: "keyboard",
            accessibilityLabel: String(localized: "Press \(shortcut.spokenDescription) again to \(command.title())"))
    }

    /// An action that could not run, with `reason` saying why.
    static func failure(_ reason: String) -> BrowserNotice {
        BrowserNotice(message: reason, systemImage: "exclamationmark.triangle.fill")
    }
}
