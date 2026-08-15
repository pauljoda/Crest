enum BrowserExtensionCompatibilityPolicy {
    static let iCloudPasswordsExtensionID =
        "pejdijmoenmkgeppbflobdenhhabjlaj"

    static func assess(
        extensionID: String? = nil,
        requestedPermissions: [String],
        source: BrowserExtensionCompatibilitySource,
        nativeMessagingCapability: BrowserExtensionNativeMessagingCapability,
        iCloudPasswordsCapability: BrowserICloudPasswordsCapability = .available
    ) -> BrowserExtensionCompatibilityAssessment {
        let requestsNativeMessaging = requestedPermissions.contains(
            "nativeMessaging"
        )
        var issues: [BrowserExtensionCompatibilityIssue] = []

        if requestsNativeMessaging {
            let blockingKind: BrowserExtensionCompatibilityIssueKind?
            switch source {
            case .safariAppExtensionBundle:
                blockingKind = .foreignSafariNativeHandler
            case .unpackedPackage:
                blockingKind = .unverifiedNativeMessaging
            case .mozillaAddons:
                blockingKind = .unsupportedMozillaNativeMessaging
            case .chromeWebStore
            where nativeMessagingCapability == .available:
                blockingKind = nil
            case .chromeWebStore:
                blockingKind = .nativeMessagingUnavailable
            }
            if let blockingKind {
                issues.append(
                    BrowserExtensionCompatibilityIssue(
                        kind: blockingKind,
                        isBlocking: true
                    )
                )
            }
        }

        if requestsNativeMessaging,
            source == .chromeWebStore,
            extensionID == Self.iCloudPasswordsExtensionID,
            iCloudPasswordsCapability != .available
        {
            issues.append(
                BrowserExtensionCompatibilityIssue(
                    kind: .knownRuntimeLimitation,
                    isBlocking: false
                )
            )
        }

        return BrowserExtensionCompatibilityAssessment(issues: issues)
    }
}
