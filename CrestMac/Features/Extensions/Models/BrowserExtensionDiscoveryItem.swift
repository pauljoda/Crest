struct BrowserExtensionDiscoveryItem: Equatable, Identifiable {
    let candidate: BrowserSafariWebExtensionCandidate
    let source: BrowserExtensionDiscoverySource

    var id: String { candidate.id }

    init(candidate: BrowserSafariWebExtensionCandidate) {
        self.candidate = candidate
        source = .safariApplication(
            name: candidate.applicationDisplayName
        )
    }
}
