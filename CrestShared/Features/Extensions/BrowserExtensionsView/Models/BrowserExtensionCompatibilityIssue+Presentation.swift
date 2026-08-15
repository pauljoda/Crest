extension BrowserExtensionCompatibilityIssue {
    var message: String {
        BrowserExtensionCompatibilityPresentation.message(for: kind)
    }
}
