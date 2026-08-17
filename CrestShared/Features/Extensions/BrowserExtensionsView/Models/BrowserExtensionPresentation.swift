import Foundation

extension BrowserExtensionAccessDecision {
    var title: LocalizedStringResource {
        switch self {
        case .ask:
            "Ask"
        case .allow:
            "Allow"
        case .block:
            "Block"
        }
    }
}

extension BrowserExtensionCompatibilityError: LocalizedError {
    var errorDescription: String? {
        assessment.blockingIssues.map(\.message).joined(separator: "\n")
    }
}

extension BrowserExtensionCompatibilityIssue {
    var message: String {
        BrowserExtensionCompatibilityPresentation.message(for: kind)
    }
}

extension BrowserExtensionPermissionRestoreError: LocalizedError {
    var errorDescription: String? {
        let patterns = droppedHostPatterns.sorted().joined(separator: ", ")
        return """
            Crest could not restore website access for \(patterns). \
            Grant website access again in Extensions settings.
            """
    }
}

struct BrowserExtensionIssuePresentation: Equatable {
    let title: String
    let message: String
    let technicalDetails: [String]
}

enum BrowserExtensionCompatibilityPresentation {
    static func message(
        for kind: BrowserExtensionCompatibilityIssueKind
    ) -> String {
        switch kind {
        case .nativeMessagingUnavailable:
            String(
                localized:
                    "This Crest build can’t launch native companion apps. Install the official Crest for Mac release and the companion app to enable this extension."
            )
        case .unverifiedNativeMessaging:
            String(
                localized:
                    "Crest blocks native companion access for unpacked extensions because their identity can’t be verified. Install the signed Chrome Web Store version instead."
            )
        case .foreignSafariNativeHandler:
            String(
                localized:
                    "This Safari extension depends on a native handler that belongs to its Safari app and can’t be reused by Crest. Install the extension’s Chrome Web Store version in Crest for Mac instead."
            )
        case .knownRuntimeLimitation:
            String(
                localized:
                    "Password AutoFill won’t work in this Crest build. Apple requires Crest to be signed with the managed Web Browser Public Key Credential entitlement before its password helper will connect. This build does not have that entitlement."
            )
        }
    }

    static var blockingMessages: Set<String> {
        Set(
            BrowserExtensionCompatibilityIssueKind.allCases.map(
                message(for:)
            )
        )
    }
}

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
