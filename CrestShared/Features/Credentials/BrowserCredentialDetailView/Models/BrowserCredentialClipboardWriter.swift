typealias BrowserCredentialClipboardWriter =
    @MainActor (
        BrowserCredentialSecretLease
    ) -> Bool
