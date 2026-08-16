import Foundation

enum BrowserExtensionSummaryPresentation {
    static func detailText(
        for summary: BrowserExtensionSummary,
        iCloudPasswordsCapability: BrowserICloudPasswordsCapability =
            .currentBuild
    ) -> String {
        let state = stateTitle(
            for: summary,
            iCloudPasswordsCapability: iCloudPasswordsCapability
        )
        let permissions = countLabel(
            summary.requestedPermissions.count,
            singular: String(localized: "permission"),
            plural: String(localized: "permissions")
        )
        let siteRules = countLabel(
            summary.requestedHosts.count,
            singular: String(localized: "site rule"),
            plural: String(localized: "site rules")
        )
        return "\(state) · \(permissions) · \(siteRules)"
    }

    static func issue(
        for summary: BrowserExtensionSummary,
        iCloudPasswordsCapability: BrowserICloudPasswordsCapability =
            .currentBuild
    ) -> BrowserExtensionIssuePresentation? {
        if isICloudPasswords(summary),
            iCloudPasswordsCapability != .available
        {
            return BrowserExtensionIssuePresentation(
                title: String(
                    localized: "iCloud Passwords needs Apple browser approval"
                ),
                message: BrowserExtensionCompatibilityPresentation.message(
                    for: .knownRuntimeLimitation
                ),
                technicalDetails: summary.errors
            )
        }

        guard summary.needsAttention else { return nil }

        if summary.id == "com.1password.safari.extension",
            summary.requestedPermissions.contains("nativeMessaging")
        {
            return BrowserExtensionIssuePresentation(
                title: String(
                    localized: "1Password can’t connect to its companion app"
                ),
                message: String(
                    localized:
                        "Sign-in, unlocking, and filling won’t work through the Safari extension in Crest. The compatible route requires 1Password for Mac, the Chrome Web Store extension, the official Crest for Mac release, and adding Crest as a trusted browser in 1Password."
                ),
                technicalDetails: summary.errors
            )
        }

        if let message = summary.compatibilityAssessment.blockingIssues.first
            .map({
                BrowserExtensionCompatibilityPresentation.message(
                    for: $0.kind
                )
            })
            ?? summary.errors.first(where: {
                BrowserExtensionCompatibilityPresentation.blockingMessages
                    .contains($0)
            })
        {
            return BrowserExtensionIssuePresentation(
                title: String(localized: "This extension can’t run in Crest"),
                message: message,
                technicalDetails: []
            )
        }

        return BrowserExtensionIssuePresentation(
            title: String(localized: "This extension ran into a problem"),
            message: String(
                localized:
                    "Some features may not work correctly. Try turning the extension off and back on. If the problem continues, update or reinstall it."
            ),
            technicalDetails: summary.errors
        )
    }

    private static func stateTitle(
        for summary: BrowserExtensionSummary,
        iCloudPasswordsCapability: BrowserICloudPasswordsCapability
    ) -> String {
        if summary.needsAttention {
            return String(localized: "Needs attention")
        }
        if summary.isEnabled,
            isICloudPasswords(summary),
            iCloudPasswordsCapability != .available
        {
            return String(localized: "Limited compatibility")
        }
        if summary.isLoaded {
            return String(localized: "Running")
        }
        return summary.isEnabled
            ? String(localized: "Needs attention")
            : String(localized: "Off")
    }

    private static func isICloudPasswords(
        _ summary: BrowserExtensionSummary
    ) -> Bool {
        summary.id
            == BrowserExtensionCompatibilityPolicy
            .iCloudPasswordsExtensionID
            && summary.compatibilitySource == .chromeWebStore
            && summary.requestedPermissions.contains("nativeMessaging")
    }

    private static func countLabel(
        _ count: Int,
        singular: String,
        plural: String
    ) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
}
