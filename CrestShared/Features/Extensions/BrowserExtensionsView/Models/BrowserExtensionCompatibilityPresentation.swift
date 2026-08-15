import Foundation

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
        case .unsupportedMozillaNativeMessaging:
            String(
                localized:
                    "Crest verifies native companion access for Chrome Web Store extensions only. This Firefox add-on’s companion connection isn’t available yet; install its Chrome Web Store version in Crest for Mac instead."
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
